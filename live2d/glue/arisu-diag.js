// Why her face is blank, told to the desk instead of to nobody.
//
// A Live2D page that fails is a transparent canvas over lain's own backdrop:
// no picture, no message, and the console is on a device nobody has a cable
// to. It happened twice on 2026-09-13 -- Chrome with graphics acceleration off
// (getContext('webgl2') null, a TypeError, nothing on screen), then Safari on
// the same Mac with a cause nobody could see from here.
//
// So this page reports. Loaded first, before Core and the bundle, so it hears
// their errors too. It posts one report to /arisu/diag once the model has had
// time to draw, plus any error after that, and it puts a line of text on the
// face when there is nothing else to show. `GET /arisu/diag` reads them back.

(function () {
  'use strict';

  var CHECK_MS = 12000;       // the bundle, Core and a 2048 texture set, on a phone
  var MAX_ERRORS = 20;
  var errors = [];
  var sent = false;

  function note(kind, msg) {
    if (errors.length >= MAX_ERRORS) return;
    errors.push({ t: Math.round(performance.now()), kind: kind,
                  msg: String(msg).slice(0, 500) });
    if (sent) send('late-error');
  }

  window.addEventListener('error', function (e) {
    var where = e.filename ? ' @ ' + e.filename.split('/').pop() + ':' + e.lineno : '';
    note('error', (e.message || (e.target && e.target.src) || 'error') + where);
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason;
    note('rejection', r && (r.stack || r.message) || r);
  });
  var consoleError = console.error;
  console.error = function () {
    note('console', Array.prototype.join.call(arguments, ' '));
    return consoleError.apply(console, arguments);
  };

  // What the browser offers, asked on a scratch canvas so the real one is
  // untouched. webgl2 is what lappglmanager asks for; webgl1 tells a disabled
  // GPU apart from a browser that only lacks version 2.
  function glReport() {
    var out = {};
    try {
      var c = document.createElement('canvas');
      var gl2 = c.getContext('webgl2');
      out.webgl2 = !!gl2;
      out.webgl1 = !!(gl2 || document.createElement('canvas').getContext('webgl'));
      var gl = gl2 || null;
      var dbg = gl && gl.getExtension('WEBGL_debug_renderer_info');
      if (dbg) out.renderer = String(gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL));
      if (gl) out.maxTexture = gl.getParameter(gl.MAX_TEXTURE_SIZE);
    } catch (e) {
      out.threw = String(e);
    }
    return out;
  }

  function report(reason) {
    var canvas = document.querySelector('canvas');
    return {
      reason: reason,
      page: location.pathname + location.search,
      ua: navigator.userAgent,
      framed: window.self !== window.top,
      visible: document.visibilityState,
      model: window.ArisuFace ? window.ArisuFace.model : null,
      rendered: typeof window.__arisuParam === 'function',
      canvas: canvas ? canvas.width + 'x' + canvas.height : null,
      gl: glReport(),
      errors: errors
    };
  }

  function send(reason) {
    sent = true;
    try {
      fetch('/arisu/diag', {
        method: 'POST', keepalive: true,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(report(reason))
      }).catch(function () {});
    } catch (e) { /* nowhere left to report to */ }
  }

  function show(text) {
    var el = document.getElementById('arisu-diag');
    if (!el) {
      el = document.createElement('div');
      el.id = 'arisu-diag';
      el.style.cssText = [
        'position:fixed', 'left:50%', 'top:40%', 'transform:translate(-50%,-50%)',
        'max-width:80vw', 'text-align:center', 'color:#fff',
        'font:14px/1.5 -apple-system,system-ui,sans-serif', 'opacity:.8',
        'pointer-events:none', 'z-index:10'
      ].join(';');
      document.body.appendChild(el);
    }
    el.textContent = text;
  }

  // The frame hook only runs while the page is painted, so a hidden tab would
  // read as a dead face. Start the clock when it is actually on screen.
  function check() {
    var r = report('check');
    if (r.rendered) return send('ok');
    send('no-face');
    show(!r.gl.webgl1
      ? 'Her face needs WebGL, and this browser has it switched off.'
      : 'Her face did not load. The desk has the details.');
  }

  function arm() {
    if (document.visibilityState === 'visible') {
      setTimeout(check, CHECK_MS);
    } else {
      document.addEventListener('visibilitychange', function once() {
        if (document.visibilityState !== 'visible') return;
        document.removeEventListener('visibilitychange', once);
        setTimeout(check, CHECK_MS);
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', arm);
  } else {
    arm();
  }
})();
