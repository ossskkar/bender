// The scene behind and around the 2D models — background, room colour, how big
// the model sits and where, and which expressions a rig uses.
//
// Why this exists as its own file. Her Live2D artwork is not ours: the body,
// clothes and face are baked into each sample's .moc3 and its texture atlases,
// under Live2D's Free Material License. What IS ours is everything around the
// artwork -- the ground it stands on, how much of the screen it fills, where in
// the frame it sits, and which of a rig's expressions get used for which state.
// Those four are this file.
//
// It is a classic script loaded before the module bundle, so it is ready before
// any SDK code runs. Three consumers read it:
//
//   src/lapplive2dmanager.ts   display.scale / display.x / display.y
//   src/lappdelegate.ts        background and room colour, on their own canvas
//   arisu-face.js              expressions.<model>.states / .reactions
//
// Everything comes from the URL, so a face page is configured by whoever links
// to it and nothing has to be saved twice:
//
//   ?bg=gradient&room=4a2f6b&scale=1.15&y=-0.05&expr=0
//
// `?bg=classroom` uses the SDK's own back_class_normal.png. An image path is
// allowed too, and is resolved against this page:
//
//   ?bg=images/room.png
//
// Per-model expression overrides are the one thing too big for a URL, so they
// come from the host instead: put `window.ArisuScenePreset` on the page before
// this script loads and its `expressions` merges over the defaults.

(function () {
  'use strict';

  var params = new URLSearchParams(window.location.search);

  // The preset, if the host page set one. Merged field by field so a host can
  // name only what it means to change.
  var preset = (typeof window !== 'undefined' && window.ArisuScenePreset) || {};

  // A tint is three 0..255 numbers, given as `?room=` / `?tint=` in hex, with
  // or without the hash. Anything unparseable is ignored rather than thrown --
  // a bad query string must never be why her face is blank.
  function tint(v, fallback) {
    if (typeof v !== 'string') return fallback;
    var m = v.trim().replace(/^#/, '').match(/^([0-9a-f]{3}|[0-9a-f]{6})$/i);
    if (!m) return fallback;
    var h = m[1];
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    return [parseInt(h.slice(0, 2), 16),
            parseInt(h.slice(2, 4), 16),
            parseInt(h.slice(4, 6), 16)];
  }

  // A number from the URL, clamped, with a floor on the scale: at 0 the model is
  // invisible and the page reads as broken rather than as configured.
  function num(raw, fallback, lo, hi) {
    if (raw == null || raw === '') return fallback;
    var n = parseFloat(raw);
    if (!isFinite(n)) return fallback;
    return Math.min(hi, Math.max(lo, n));
  }

  // A colour from anywhere -- the URL, a host preset, the settings panel -- as
  // the one shape tint() understands. Accepts '#rrggbb', 'rrggbb' and
  // [r, g, b], so a caller never has to know which the parser wants.
  function _hex(v) {
    if (Array.isArray(v)) {
      return v.slice(0, 3).map(function (n) {
        var x = Math.max(0, Math.min(255, Math.round(Number(n) || 0)));
        return (x < 16 ? '0' : '') + x.toString(16);
      }).join('');
    }
    return String(v == null ? '' : v).trim().replace(/^#/, '');
  }

  var DEFAULT_ROOM = [6, 8, 12];

  // `?bg=` accepts the two words, "off" for no background at all, or a path.
  // A bare word that is none of those is treated as a path, which is the useful
  // reading -- `?bg=night.png` should work without a scheme.
  var bgRaw = params.get('bg');
  var bg = { mode: 'gradient', image: '' };
  if (bgRaw === 'off' || bgRaw === 'none' || bgRaw === 'clear') {
    bg.mode = 'none';
  } else if (bgRaw === 'gradient' || bgRaw === 'flat') {
    bg.mode = bgRaw;
  } else if (bgRaw === 'classroom') {
    bg.mode = 'image';
    bg.image = './Resources/back_class_normal.png';
  } else if (bgRaw) {
    bg.mode = 'image';
    bg.image = bgRaw;
  }
  if (preset.background && typeof preset.background === 'object') {
    if (preset.background.mode) bg.mode = preset.background.mode;
    if (preset.background.image) bg.image = preset.background.image;
  }
  // A background image has to actually load. ArisuScene.imageFailed() is how
  // the delegate finds out it did not, so it can fall back instead of leaving
  // the model on nothing.
  bg.failed = false;

  var room = tint(params.get('room') || params.get('tint'),
                  (preset.room && preset.room.slice) ? preset.room.slice() : DEFAULT_ROOM);

  // depth: how far the bottom of the frame falls away from the room colour at
  // the top. 0 is a flat wall, 1 is black at the floor.
  var depth = num(params.get('depth'), preset.depth == null ? 0.55 : preset.depth, 0, 1);

  // display. Scale multiplies the SDK's own fit, so 1 is exactly what shipped.
  // x and y are fractions of the canvas and move the model, +y up.
  var pd = preset.display || {};
  var display = {
    scale: num(params.get('scale'), pd.scale, 0.1, 4),
    x: num(params.get('x'), pd.x, -2, 2),
    y: num(params.get('y'), pd.y, -2, 2)
  };
  if (display.scale == null) display.scale = 1;
  if (display.x == null) display.x = 0;
  if (display.y == null) display.y = 0;

  // The wash is the page's own tint over the whole scene -- vignette, haze, a
  // colour cast. It is painted on the same canvas as the background, under the
  // model, so the model itself is never tinted by it.
  var po = preset.overlay || {};
  var overlay = {
    tint: tint(params.get('wash'), po.tint),
    alpha: num(params.get('washAlpha'), po.alpha, 0, 1)
  };
  if (overlay.alpha == null) overlay.alpha = 0;

  function mergeExpressions(base) {
    var p = preset.expressions;
    if (!p) return base;
    for (var model in p) {
      if (!Object.prototype.hasOwnProperty.call(p, model)) continue;
      var into = base[model] || (base[model] = { states: {}, reactions: {} });
      var from = p[model] || {};
      if (from.states) {
        into.states = into.states || {};
        for (var s in from.states) into.states[s] = from.states[s];
      }
      if (from.reactions) {
        into.reactions = into.reactions || {};
        for (var r in from.reactions) into.reactions[r] = from.reactions[r];
      }
    }
    return base;
  }

  var image = null;
  var imageSrc = null;

  // The delegate registers its repaint here. Without it, a runtime change would
  // take effect only on the next resize, which reads as a setting that did not
  // save -- the exact failure the settings panel must not have.
  var redraw = null;

  window.ArisuScene = {
    background: bg,
    room: room,
    depth: depth,
    display: display,
    overlay: overlay,

    // Loaded lazily, once, the first time a frame asks for it. Loading eagerly
    // would fetch the classroom on every page that never shows it.
    backgroundImage: function () {
      if (bg.mode !== 'image' || !bg.image) return null;
      // A new path means a new image, so the old one is dropped rather than
      // reused -- otherwise changing the background would keep painting the
      // previous one until a reload.
      if (imageSrc !== bg.image) {
        imageSrc = bg.image;
        image = new Image();
        bg.failed = false;
        image.onerror = function () { bg.failed = true; if (redraw) redraw(); };
        image.onload = function () { if (redraw) redraw(); };
        image.src = bg.image;
        return null;
      }
      return image && image.complete && image.naturalWidth ? image : null;
    },

    imageFailed: function () { return bg.failed; },

    // The delegate's repaint, once it exists.
    onRedraw: function (fn) { redraw = fn; if (fn) fn(); },

    // Change the scene on a live page. The URL is where a scene comes from, but
    // the settings panel changes one field at a time long after load, and
    // re-navigating the iframe to apply a slider would restart her model on
    // every drag. Anything not named in the patch is left as it is.
    apply: function (patch) {
      if (!patch) return window.ArisuScene;
      if (patch.bg) {
        if (patch.bg.mode) bg.mode = patch.bg.mode;
        if (patch.bg.image != null) bg.image = patch.bg.image;
        if (patch.bg.mode === 'none') bg.failed = false;
      }
      if (patch.room) {
        var r = tint(_hex(patch.room), null);
        if (r) { room[0] = r[0]; room[1] = r[1]; room[2] = r[2]; }
      }
      if (patch.depth != null) depth = num(String(patch.depth), depth, 0, 1);
      if (patch.display) {
        if (patch.display.scale != null) {
          display.scale = num(String(patch.display.scale), display.scale, 0.1, 4);
        }
        if (patch.display.x != null) {
          display.x = num(String(patch.display.x), display.x, -2, 2);
        }
        if (patch.display.y != null) {
          display.y = num(String(patch.display.y), display.y, -2, 2);
        }
      }
      if (patch.overlay) {
        var ot = patch.overlay.tint ? tint(_hex(patch.overlay.tint), null) : null;
        if (ot) overlay.tint = ot;
        if (patch.overlay.alpha != null) {
          overlay.alpha = num(String(patch.overlay.alpha), overlay.alpha, 0, 1);
        }
      }
      if (patch.expressions) {
        preset.expressions = preset.expressions || {};
        for (var m in patch.expressions) {
          if (!Object.prototype.hasOwnProperty.call(patch.expressions, m)) continue;
          var from = patch.expressions[m] || {};
          var into = preset.expressions[m] || (preset.expressions[m] = {});
          if (from.states) {
            into.states = into.states || {};
            for (var s in from.states) into.states[s] = from.states[s];
          }
          if (from.reactions) {
            into.reactions = into.reactions || {};
            for (var rr in from.reactions) into.reactions[rr] = from.reactions[rr];
          }
        }
        // arisu-face.js resolves its table on every question rather than
        // caching one at load, so a new override is live from the next frame
        // with nothing to refresh.
      }
      if (redraw) redraw();
      return window.ArisuScene;
    },

    // [r, g, b] or '#rrggbb' or 'rrggbb', as the settings panel sends it.
    setRoom: function (v) {
      var r = tint(_hex(v), null);
      if (r) {
        room[0] = r[0]; room[1] = r[1]; room[2] = r[2];
        if (redraw) redraw();
      }
    },

    // The expression table with any host overrides already merged in.
    expressions: function (base) { return mergeExpressions(base); },

    // A flat [r,g,b] for the floor of the gradient.
    floor: function () {
      return [Math.round(room[0] * (1 - depth)),
              Math.round(room[1] * (1 - depth)),
              Math.round(room[2] * (1 - depth))];
    },

    // What the scene actually came out as, read back off the DOM -- not what
    // the config says it should be. A background that is configured and a
    // background that is drawn are different claims, and only the second one is
    // worth reporting. The delegate owns the canvas, so this finds it by id.
    //
    // Sampled down the middle rather than at a corner: a corner of the gradient
    // is nearly the room colour either way, and would report a flat wall as a
    // working gradient.
    probe: function () {
      var canvas = document.getElementById('arisu-scene');
      if (!canvas) return { drawn: false, why: 'no canvas' };
      var c = canvas.getContext('2d');
      var out = {
        drawn: canvas.width > 1 && canvas.height > 1,
        w: canvas.width,
        h: canvas.height,
        mode: bg.mode,
        image: bg.image || null,
        failed: bg.failed,
        room: room,
        depth: depth,
        display: display,
        samples: []
      };
      if (!c) { out.why = 'no 2d context'; return out; }
      try {
        var mid = Math.round(canvas.width / 2);
        [0.02, 0.5, 0.98].forEach(function (f) {
          var y = Math.min(canvas.height - 1, Math.round(canvas.height * f));
          var p = c.getImageData(mid, y, 1, 1).data;
          out.samples.push([p[0], p[1], p[2], p[3]]);
        });
        // A gradient is only a gradient if the ends differ. This is the one
        // thing a screenshot would tell us and a config dump would not.
        var a = out.samples[0], b = out.samples[2];
        out.spread = Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]);
        out.thumb = canvas.toDataURL ? canvas.toDataURL('image/png') : '';
      } catch (e) {
        out.why = String(e);
      }
      return out;
    }
  };

  // ---------------------------------------------------------------------------
  // PROBE. Reachable only with ?probe=1, which nothing links to. It writes what
  // the scene and the face actually came out as into the document, so a headless
  // browser can be asked for the truth instead of a screenshot being squinted
  // at: `chrome --headless --dump-dom '<url>?probe=1'`. Delete this block and
  // the URL parameter with it; nothing else reads it.
  // ---------------------------------------------------------------------------
  if (params.get('probe')) {
    setTimeout(function () {
      var report = { scene: window.ArisuScene.probe() };
      var face = window.ArisuFace;
      if (face) {
        report.model = face.model;
        report.expression = face.takePendingExpression();
        report.states = {};
        // The table itself is private, so ask it the same question the delegate
        // asks -- what expression does this state resolve to.
        (face.states || []).forEach(function (s) {
          face.setState(s);
          report.states[s] = face.takePendingExpression();
        });
        // refresh() puts the live state's expression back, since the loop above
        // left the table parked on the last state it sampled.
        face.refresh();
      }
      var el = document.createElement('pre');
      el.id = 'arisu-probe';
      el.textContent = JSON.stringify(report);
      document.body.appendChild(el);
      document.title = 'PROBE-DONE';
    }, 4000);
  }
})();
