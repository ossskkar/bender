#!/usr/bin/env node
// Ask a real Chrome what the Live2D scene actually rendered.
//
// Usage:
//   node live2d-probe.mjs <url> [waitMs] [--preset <js-object>]
//   node live2d-probe.mjs --batch <cases-file> [waitMs]
//
// Prints one JSON object per line, in the order given. In batch mode the cases
// file holds one case per line: `url<TAB>preset-js`, the preset optional.
//
// Why a real browser: a scene that is configured and a scene that is drawn are
// two different claims, and only the second one is worth anything. This reads
// the rendered canvas pixels back and reports what is actually there.
//
// Why not --dump-dom: on this Mac it returns nothing at all in the new headless
// mode. The DevTools protocol is the reliable route.
//
// Why SwiftShader: this Mac's Chrome has hardware acceleration off, and headless
// Chrome has no GPU. Without a software GL every model canvas would have no
// context at all, and every check about the model would be vacuously true. It is
// slow and it is not a fidelity test -- it answers "did the model draw, and
// where", which is the question here.
//
// Why batch mode is not a nicety: each case needs software WebGL, and a fresh
// Chrome per case piled up SwiftShader contexts until some pages never drew a
// frame at all. The probe then reported that, correctly and uselessly, as an
// empty canvas. One browser, navigated through the list, is faster and stops the
// runs from poisoning each other.

import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// How long to wait for the model to have drawn, per case. Generous, because
// software rasterisation of a 2048px model at about one frame a second is
// genuinely slow, and a false "it never drew" costs more than a slow run.
const DRAW_DEADLINE_MS = 60000;

const GL_FLAGS = [
  '--use-gl=angle',
  '--use-angle=swiftshader',
  '--enable-unsafe-swiftshader',
];

// Injected before any page script runs.
//
// preserveDrawingBuffer, or readPixels after the frame has been presented
// returns an empty buffer -- the delegate's own getContext call has to be given
// the attribute.
//
// The frame counter is how a rAF loop that never fired is told apart from a
// model that failed to draw. Headless Chrome has no compositor, so its
// requestAnimationFrame runs at roughly one frame a second, and an empty canvas
// looks identical either way.
const PRELUDE = `
(function () {
  var orig = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function (type, attrs) {
    if (type === 'webgl2' || type === 'webgl' || type === 'experimental-webgl') {
      attrs = Object.assign({}, attrs || {}, { preserveDrawingBuffer: true });
    }
    return orig.call(this, type, attrs);
  };
  window.__frames = 0;
  var raf = window.requestAnimationFrame;
  window.requestAnimationFrame = function (cb) {
    return raf.call(window, function (t) { window.__frames++; return cb(t); });
  };
})();
`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- arguments

const argv = process.argv.slice(2);
function takeFlag(name) {
  const i = argv.indexOf(name);
  if (i < 0) return null;
  const v = argv[i + 1];
  argv.splice(i, 2);
  return v;
}

const batchFile = takeFlag('--batch');
const preset = takeFlag('--preset');
const target = argv[0];
const waitMs = Number(argv[1] || 9000);

if (!batchFile && !target) {
  console.error('usage: live2d-probe.mjs <url> [waitMs] [--preset <js>]');
  console.error('       live2d-probe.mjs --batch <cases-file> [waitMs]');
  process.exit(2);
}

// ---------------------------------------------------------------- the browser

function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    let id = 0;
    const pending = new Map();
    ws.addEventListener('open', () => resolve({
      send(method, params) {
        return new Promise((res, rej) => {
          const mid = ++id;
          pending.set(mid, { res, rej });
          ws.send(JSON.stringify({ id: mid, method, params }));
        });
      },
      close() { ws.close(); },
    }));
    ws.addEventListener('error', reject);
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (!msg.id || !pending.has(msg.id)) return;
      const { res, rej } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) rej(new Error(JSON.stringify(msg.error)));
      else res(msg.result);
    });
  });
}

async function launch() {
  const port = 9222 + Math.floor(Math.random() * 500);
  const profile = mkdtempSync(join(tmpdir(), 'arisu-probe-'));
  const chrome = spawn(CHROME, [
    '--headless=new',
    `--user-data-dir=${profile}`,
    `--remote-debugging-port=${port}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--no-sandbox',
    '--window-size=800,1000',
    ...GL_FLAGS,
    'about:blank',
  ], { stdio: 'ignore' });

  let page = null;
  let died = null;
  chrome.on('exit', (code, signal) => {
    died = 'chrome exited early (code ' + code +
           (signal ? ', signal ' + signal : '') + ')';
  });

  // Twelve seconds, not two minutes of quiet polling. A Chrome that aborts on
  // launch never answers, and waiting politely turns an obvious environment
  // failure into a mystery -- which is exactly what happened on 2026-09-14.
  for (let i = 0; i < 120 && !page; i++) {
    if (died) break;
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      page = list.find((t) => t.type === 'page');
    } catch { /* not up yet */ }
    if (!page) await sleep(100);
  }
  if (!page) {
    chrome.kill('SIGKILL');
    throw new Error(
      'Chrome never came up: ' + (died || 'it answered nothing on its port') +
      '\n      Headless Chrome on macOS registers as a GUI application, so this\n' +
      '      aborts inside HIServices _RegisterApplication when the desktop\n' +
      '      session is unavailable -- a locked screen is enough. Check that\n' +
      '      Chrome opens normally, then retry.');
  }

  const cdp = await connect(page.webSocketDebuggerUrl);
  await cdp.send('Runtime.enable');
  await cdp.send('Page.enable');
  await cdp.send('Page.addScriptToEvaluateOnNewDocument', { source: PRELUDE });
  return { chrome, cdp };
}

async function evaluate(cdp, expression, contextId) {
  const params = { expression, returnByValue: true, awaitPromise: true };
  if (contextId) params.contextId = contextId;
  const r = await cdp.send('Runtime.evaluate', params);
  if (r.exceptionDetails) {
    throw new Error(r.exceptionDetails.exception?.description || 'eval threw');
  }
  return r.result.value;
}

// The document that actually holds the scene, and the window around it.
//
// The face page has the model canvas at the top level; the client page puts the
// whole face in a same-origin iframe. Measuring `document` therefore measures
// an empty top-level page on the client and reports "no model canvas" -- a
// confident lie about a page that is working. Everything below measures D, and
// D is whichever document has the scene in it.
//
// Same-origin only, by design: a cross-origin iframe cannot be read, and the
// only one here is lain's own.
const FACE_DOC = `
function __arisuFaceDoc(W, D) {
  try {
    var frames = [].slice.call(D.querySelectorAll('iframe'));
    for (var i = 0; i < frames.length; i++) {
      try {
        var w = frames[i].contentWindow;
        if (w && w.document && w.document.getElementById('arisu-scene')) {
          return { W: w, D: w.document };
        }
      } catch (e) { /* cross-origin; not ours */ }
    }
  } catch (e) { /* no iframes */ }
  return { W: W, D: D };
}
`;

// A measurement body, run with `W`, `D` and `face` in scope.
const inFace = (body) => `(function(){
  ${FACE_DOC}
  var face = __arisuFaceDoc(window, document);
  var W = face.W, D = face.D;
  return (function(){ ${body} }).call(W);
})()`;

// A child frame's url and frameId -- the face iframe on the parent page.
async function childFrames(cdp) {
  const { frameTree } = await cdp.send('Page.getFrameTree');
  const out = [];
  const walk = (node) => {
    if (node.frame && node.frame.parentId) out.push(node.frame);
    (node.childFrames || []).forEach(walk);
  };
  walk(frameTree);
  return out;
}

// Read a child frame's own window, from the parent's context.
//
// NOT Page.createIsolatedWorld: an isolated world gets a *different* window
// object, so `window.ArisuScene` inside it is undefined however well the page
// loaded. That produced a confident "the parent never passed the scene across"
// for a parent that was passing it perfectly -- the frame's own window is the
// only place the answer exists, and the face iframe is same-origin, so the
// parent can simply reach into it.
//
// The iframe is found by its URL rather than by index, so a page with more than
// one iframe -- or one whose frames are nested -- cannot silently mismatch. The
// first iframe is the fallback, for the case where the frame has since navigated
// and its URL no longer matches what the frame tree reported.
async function evalInFrame(cdp, frameUrl, expression) {
  const wrapper = `(function(){
    var frames = [].slice.call(document.querySelectorAll('iframe'));
    var f = null;
    for (var i = 0; i < frames.length; i++) {
      try {
        if (frames[i].contentWindow
            && frames[i].contentWindow.location.href === ${JSON.stringify(frameUrl)}) {
          f = frames[i]; break;
        }
      } catch (e) { /* cross-origin frame; not ours */ }
    }
    if (!f) f = frames[0];
    if (!f) return { evalError: 'no iframe to read' };
    try {
      var w = f.contentWindow;
      if (!w) return { evalError: 'no contentWindow' };
      return (function(){ ${expression} }).call(w);
    } catch (e) { return { evalError: String(e) }; }
  })()`;
  return evaluate(cdp, wrapper);
}

// ---------------------------------------------------------------- measurement

// Wait until the model has really been drawn. Two conditions, and a frame count
// alone is neither of them:
//
//   __arisuParam exists -- the SDK's per-frame hook has run, so the manager is
//                         alive and updating the model
//   pixels are lit      -- readPixels on the model canvas returns something
//
// The first frames can run before the manager has drawn anything, and reading
// then reports a working model as a blank one. It did exactly that once and sent
// me hunting a bug that was not there.
async function waitForDraw(cdp, readiness) {
  const deadline = Date.now() + DRAW_DEADLINE_MS;
  while (Date.now() < deadline) {
    Object.assign(readiness, await evaluate(cdp, inFace(`
      var m = [].filter.call(D.querySelectorAll('canvas'),
                              function(x){ return x.id !== 'arisu-scene'; })[0];
      var lit = 0;
      try {
        var g = m && m.getContext('webgl2');
        if (g && !g.isContextLost()) {
          var w = m.width, h = m.height;
          var px = new Uint8Array(w * h * 4);
          g.readPixels(0, 0, w, h, g.RGBA, g.UNSIGNED_BYTE, px);
          for (var i = 3; i < px.length; i += 4) if (px[i] >= 8) lit++;
        }
      } catch (e) { /* the measure below reports it */ }
      // A background image is a fetch, and until it lands the scene shows the
      // gradient underneath. Wait for it to be genuinely loaded, not merely
      // "not pending": imageFailed() also goes true when a load is aborted, so
      // reading not-pending as ready measured the fallback and reported it as
      // the image. The static server these runs use is single-threaded, so the
      // image queues behind the model's texture sets -- production is threaded,
      // which makes this wait an artefact of the rig, not of the code.
      var pending = false;
      try {
        var s = W.ArisuScene;
        if (s && s.background.mode === 'image' && !s.imageFailed()) {
          var im = s.backgroundImage();
          pending = !(im && im.complete && im.naturalWidth > 0);
        }
      } catch (e) { /* no scene on this page */ }
      // Nothing to wait for when the page has no model canvas at all. The client
      // page puts the face in an iframe and measures the cue, not the model, so
      // the full draw deadline is two minutes of sleeping through nothing per
      // case -- which is how a two-case run came to take longer than the tool's
      // own timeout.
      var hasCanvas = !!D.querySelector('canvas');
      return { frames: W.__frames || 0,
               rendered: typeof W.__arisuParam === 'function',
               imagePending: pending, lit: lit, noModel: !hasCanvas };
    `)).catch(() => ({})));

    if (readiness.noModel) return;
    if (readiness.rendered && readiness.lit > 0 && !readiness.imagePending) {
      // The image is loaded, and a load that has just finished still has to be
      // painted. One beat, then the deliberate repaint below does the rest.
      await sleep(800);
      return;
    }
    await sleep(250);
  }
}

// What the scene found when it painted. Distinct from what the config says: an
// image configured, an image element that exists, and an image that reached
// drawImage are three different states, and only the last one puts pixels on
// the screen.
async function readPaint(cdp) {
  return evaluate(cdp, inFace(`
      var s = W.ArisuScene;
      if (!s) return { scene: false };
      var im = s.backgroundImage();
      return { scene: true, mode: s.background.mode, failed: s.imageFailed(),
               hasImage: !!im,
               natural: im ? [im.naturalWidth, im.naturalHeight] : null,
               complete: im ? im.complete : null };
  `)).catch((e) => ({ evalError: String(e) }));
}

// One case. `cdp` is already connected and has the prelude registered.
//
// `injectJs` is a script run at document-start, before any page script. It began
// as the scene preset (window.ArisuScenePreset) and is general now, because the
// state cue has to be driven the same way: from before the page starts, so the
// harness is in place by the time the page looks for it.
async function measure(cdp, pageUrl, injectJs) {
  const out = { url: pageUrl, ok: false };
  let injection = null;

  try {
    if (injectJs) {
      injection = await cdp.send('Page.addScriptToEvaluateOnNewDocument', {
        source: injectJs,
      });
    }

    await cdp.send('Page.navigate', { url: pageUrl });

    // The page's own probe lands about four seconds after load.
    let probe = null;
    for (let i = 0; i < Math.ceil(waitMs / 250); i++) {
      await sleep(250);
      const txt = await evaluate(cdp,
        `(function(){var e=document.getElementById('arisu-probe');
          return e ? e.textContent : '';})()`).catch(() => '');
      if (txt) { probe = JSON.parse(txt); break; }
    }

    const readiness = { frames: 0, rendered: false, imagePending: false, lit: 0 };
    await waitForDraw(cdp, readiness);

    // Repaint before measuring, deliberately. This is not a workaround, it is
    // the thing under test: the settings panel changes a field and the scene
    // repaints on the spot, through the delegate's repaint hook. Measuring
    // whatever happened to be on the canvas meant racing a redraw the page
    // schedules for its own reasons, which made one case pass and fail on
    // different runs.
    out.repaint = await evaluate(cdp, inFace(`
      if (typeof W.__arisuDrawScene !== 'function') return 'no hook';
      try { W.__arisuDrawScene(); return 'ok'; }
      catch (e) { return 'threw: ' + e; }
    `)).catch((e) => 'eval failed: ' + e);

    // What the scene found when it painted. Distinct from what the config says:
    // an image configured, an image element that exists, and an image that
    // reached drawImage are three different states, and only the last one puts
    // pixels on the screen.
    // An image that has loaded still has to reach the canvas, and the repaint
    // above can land just before it does. Retried rather than slept off: the
    // first read is what says whether it is worth waiting for.
    for (let attempt = 0; attempt < 6; attempt++) {
      out.paint = await readPaint(cdp);
      if (!(out.paint.mode === 'image' && out.paint.hasImage)) break;
      const spreadNow = await evaluate(cdp, inFace(`
        var s = W.ArisuScene;
        return s && s.probe ? (s.probe().spread) : null;
      `)).catch(() => null);
      // 122 is this room's plain gradient. A painted classroom reads ~84. Any
      // difference at all is enough -- this is a retry, not an assertion.
      if (spreadNow != null && spreadNow !== 122) break;
      await sleep(700);
      await evaluate(cdp, inFace(`
        if (W.__arisuDrawScene) { W.__arisuDrawScene(); return 'ok'; }
        return 'no hook';
      `)).catch(() => {});
      await sleep(300);
    }

    out.dom = await evaluate(cdp, inFace(`
      var canvases = [].map.call(D.querySelectorAll('canvas'), function(x){
        return { id: x.id || '(none)', w: x.width, h: x.height,
                 cw: x.clientWidth, ch: x.clientHeight,
                 z: D.defaultView.getComputedStyle(x).zIndex,
                 pos: D.defaultView.getComputedStyle(x).position };
      });
      var result = { canvases: canvases };
      try {
        var m = [].filter.call(D.querySelectorAll('canvas'),
                                function(x){ return x.id !== 'arisu-scene'; })[0];
        var g = m && (m.getContext('webgl2') || m.getContext('webgl'));
        result.gl = g
          ? (g.getParameter(g.VERSION) + ' / ' + g.getParameter(g.RENDERER)) : 'none';
        var attrs = g ? g.getContextAttributes() : null;
        result.preserveDrawingBuffer = attrs ? attrs.preserveDrawingBuffer : null;
      } catch (e) { result.gl = 'threw: ' + e; }
      return result;
    `)).catch((e) => ({ evalError: String(e) }));
    await sleep(150);

    // The page's own ground, as opposed to the iframe's canvas. On the face page
    // there is no #ground at all and these are null; on the client page they are
    // how the room reaches the screen around the model.
    out.ground = await evaluate(cdp, `(function(){
      var g = document.getElementById('ground');
      if (!g) return { ground: false };
      var cs = getComputedStyle(document.documentElement);
      return {
        ground: true,
        roomVar: (cs.getPropertyValue('--room') || '').trim(),
        tintVar: (cs.getPropertyValue('--tint') || '').trim(),
        hasRoomClass: document.body.classList.contains('has-room'),
        background: getComputedStyle(g).backgroundImage.slice(0, 120),
      };
    })()`).catch((e) => ({ evalError: String(e) }));

    out.dom = await evaluate(cdp, inFace(`
      var canvases = [].map.call(D.querySelectorAll('canvas'), function(x){
        return { id: x.id || '(none)', w: x.width, h: x.height,
                 cw: x.clientWidth, ch: x.clientHeight,
                 z: D.defaultView.getComputedStyle(x).zIndex,
                 pos: D.defaultView.getComputedStyle(x).position };
      });
      var result = { canvases: canvases };
      try {
        var m = [].filter.call(D.querySelectorAll('canvas'),
                                function(x){ return x.id !== 'arisu-scene'; })[0];
        var g = m && (m.getContext('webgl2') || m.getContext('webgl'));
        result.gl = g
          ? (g.getParameter(g.VERSION) + ' / ' + g.getParameter(g.RENDERER)) : 'none';
        var attrs = g ? g.getContextAttributes() : null;
        result.preserveDrawingBuffer = attrs ? attrs.preserveDrawingBuffer : null;
      } catch (e) { result.gl = 'threw: ' + e; }
      return result;
    `)).catch((e) => ({ evalError: String(e) }));

    // The model canvas, measured. The whole point of scale/x/y is where the
    // model lands on screen, and there is no honest way to check that from the
    // config: the SDK composes its own fit first, so what a given scale does
    // depends on the aspect ratio. Read the pixels and report the bounding box.
    out.model = await evaluate(cdp, inFace(`
      var common = { frames: W.__frames,
                     visible: D.visibilityState,
                     rendered: typeof W.__arisuParam === 'function' };
      var model = [].filter.call(D.querySelectorAll('canvas'),
                                  function(x){ return x.id !== 'arisu-scene'; })[0];
      if (!model) {
        return Object.assign(common, { drew: false, lit: 0, why: 'no model canvas' });
      }
      var g = null;
      try { g = model.getContext('webgl2'); }
      catch (e) { return Object.assign(common, { drew: false, lit: 0, why: String(e) }); }
      if (!g) return Object.assign(common, { drew: false, lit: 0, why: 'no webgl2' });
      if (g.isContextLost()) {
        return Object.assign(common, { drew: false, lit: 0, why: 'context lost' });
      }

      var w = model.width, h = model.height;
      var px = new Uint8Array(w * h * 4);
      g.readPixels(0, 0, w, h, g.RGBA, g.UNSIGNED_BYTE, px);

      // readPixels is bottom-up, so y is flipped back to screen order here.
      var minX = w, maxX = -1, minY = h, maxY = -1, lit = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (px[(y * w + x) * 4 + 3] < 8) continue;
          lit++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          var sy = h - 1 - y;
          if (sy < minY) minY = sy;
          if (sy > maxY) maxY = sy;
        }
      }
      // lit is on every return, including the empty one: the checks read it, and
      // a missing key has already been mistaken for a failed measurement once.
      if (maxX < 0) {
        return Object.assign(common, { drew: true, lit: 0, why: 'canvas empty' });
      }
      var f = function (v, d) { return Math.round((v / d) * 1000) / 1000; };
      return Object.assign(common, {
        drew: true, lit: lit, canvas: [w, h],
        coverage: Math.round((lit / (w * h)) * 1000) / 1000,
        // Fractions of the canvas, screen orientation, 0 top-left.
        box: { left: f(minX, w), right: f(maxX, w),
               top: f(minY, h), bottom: f(maxY, h) },
        centre: { x: f((minX + maxX) / 2, w), y: f((minY + maxY) / 2, h) },
        width: f(maxX - minX, w), height: f(maxY - minY, h),
      });
    `)).catch((e) => ({ drew: false, lit: 0, why: String(e) }));

    // The state cue: colour, readout and the light layer itself.
    out.cue = await evaluate(cdp, `(function(){
      var root = getComputedStyle(document.documentElement);
      var el = document.getElementById('state');
      var g = document.getElementById('glow');
      var out = {
        state: root.getPropertyValue('--state').trim(),
        glow: root.getPropertyValue('--glow').trim(),
        loud: root.getPropertyValue('--loud').trim(),
        tint: root.getPropertyValue('--tint').trim(),
        readout: el ? el.textContent.trim() : null,
        cls: el ? el.className : null,
        animated: g ? getComputedStyle(g).animationName : null,
      };
      if (g) {
        var cs = getComputedStyle(g);
        var cs2 = getComputedStyle(g, '::after');
        out.layer = {
          position: cs.position,
          // A light layer with no size paints nothing, however right its colour
          // is: position/top/right/bottom/left are what make it cover the page.
          w: g.offsetWidth, h: g.offsetHeight,
          background: cs.backgroundImage.slice(0, 60),
          opacity: cs2.opacity,
          transition: cs.transitionProperty,
        };
      }
      return out;
    })()`).catch((e) => ({ evalError: String(e) }));

    // Any child frames, and what the scene resolved to inside them. The parent
    // page carries scene parameters into the face iframe, and this is where that
    // either worked or did not.
    out.frames = [];
    const kids = await childFrames(cdp).catch(() => []);
    for (const f of kids) {
      const entry = { url: f.url };
      try {
        // `this` is the frame's own window: evalInFrame calls the body with the
        // frame's contentWindow, so `window` here would be the wrong one.
        entry.scene = await evalInFrame(cdp, f.url, `
          var s = this.ArisuScene;
          if (!s) return { hasScene: false };
          return { hasScene: true, mode: s.background.mode, image: s.background.image,
                   room: s.room, depth: s.depth, display: s.display,
                   model: this.ArisuFace ? this.ArisuFace.model : null };
        `);
      } catch (e) { entry.sceneError = String(e); }
      out.frames.push(entry);
    }

    out.readiness = readiness;
    if (probe && probe.scene) delete probe.scene.thumb;
    out.probe = probe;
    // `ok` means the scene is up and drawing, wherever it lives. On the face page
    // that is the top document, whose own probe element is the evidence; on the
    // client page the top document is only a shell and the scene is in the
    // iframe, so the frame report is. Requiring the top-level probe element on
    // both made every client-page case exit non-zero while working perfectly.
    const drewModel = !!out.model && out.model.drew && out.model.lit > 0;
    const sceneUp = !!probe
      || (out.frames || []).some((f) => f.scene && f.scene.hasScene);
    out.ok = drewModel && sceneUp;
  } catch (e) {
    out.error = String(e);
  } finally {
    if (injection && injection.identifier) {
      await cdp.send('Page.removeScriptToEvaluateOnNewDocument', {
        identifier: injection.identifier,
      }).catch(() => {});
    }
  }
  return out;
}

// ---------------------------------------------------------------- main

// The cases file is JSON: a list of {name?, url, inject?}. JSON rather than one
// case per line because `inject` is a script, and a script has newlines in it --
// a line-based format silently truncated every harness at its first newline,
// which produced a probe that ran forever on a page whose harness had been cut
// in half. A tab-separated first attempt had the same flaw for the same reason.
function loadCases(path) {
  const raw = readFileSync(path, 'utf8').trim();
  if (!raw) return [];
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) throw new Error('cases file must be a JSON array');
  return parsed.map((c) => {
    if (!c || typeof c.url !== 'string') {
      throw new Error('every case needs a url: ' + JSON.stringify(c).slice(0, 80));
    }
    return { url: c.url, inject: c.inject || null, name: c.name || '' };
  });
}

const cases = batchFile
  ? loadCases(batchFile)
  : [{ url: target, inject: preset || null, name: '' }];

let browser = null;
let exitCode = 0;
try {
  browser = await launch();
  for (const c of cases) {
    const result = await measure(browser.cdp, c.url, c.inject);
    console.log(JSON.stringify(result));
    if (!result.ok) exitCode = 1;
  }
} catch (e) {
  console.error('probe failed: ' + e);
  exitCode = 2;
} finally {
  if (browser) browser.chrome.kill('SIGKILL');
}
process.exit(exitCode);
