(function () {
  // Snapshots live in this closure, not on `window`.
  //
  // They were on window.__cue first and a page script clobbered that global: the
  // harness ran perfectly and the probe read an empty object, which reported as
  // "the page never reached the harness". A name on window is shared with every
  // other script on the page; a closure is not.
  var snaps = [];

  var realFetch = window.fetch;
  window.fetch = function (u) {
    var url = String(u);
    if (url.indexOf('/arisu/state') === 0 || url.indexOf('/arisu/commands') === 0) {
      return Promise.reject(new Error('harness: no desk'));
    }
    return realFetch.apply(this, arguments);
  };

  function snap(label) {
    var root = getComputedStyle(document.documentElement);
    var el = document.getElementById('state');
    var g = document.getElementById('glow');
    var cs = g ? getComputedStyle(g) : null;
    snaps.push({
      label: label,
      state: root.getPropertyValue('--state').trim(),
      glow: root.getPropertyValue('--glow').trim(),
      readout: el ? el.textContent.trim() : null,
      cls: el ? el.className : null,
      animated: cs ? cs.animationName : null,
      glowClass: g ? g.className : null,
      // The layer's own geometry: a rule missing its inset leaves nothing to
      // see, and "the variable is set" would not catch that.
      layer: g ? {
        w: g.offsetWidth,
        h: g.offsetHeight,
        position: cs.position,
        background: cs.backgroundImage.slice(0, 60),
        // Her voice, read from the root where it is declared. Resolving a
        // custom property through a pseudo-element is platform-dependent, and
        // a missing resolution is indistinguishable from a zero -- which is how
        // a real bug here hid once already.
        loud: parseFloat(root.getPropertyValue('--loud'))
      } : null
    });
  }

  // A promise, so the voice snapshot can wait for the 90ms transition on the
  // light. Taken synchronously it read the previous opacity and reported that
  // amplitude had no effect.
  function after(ms) {
    return new Promise(function (r) { setTimeout(r, ms); });
  }

  // Report into the DOM: the probe polls for #arisu-probe and takes its text as
  // the page's own probe result. The sentinel element is the handshake both
  // halves of this rig already use.
  function report(why) {
    var pre = document.getElementById('arisu-probe');
    if (!pre) {
      pre = document.createElement('pre');
      pre.id = 'arisu-probe';
      pre.style.display = 'none';
      document.body.appendChild(pre);
    }
    pre.textContent = JSON.stringify({ cue: { snaps: snaps, why: why } });
  }

  var tries = 0;
  (function wait() {
    if (typeof window.__setState !== 'function'
        || typeof window.__setAmplitude !== 'function'
        || !document.getElementById('state')) {
      if (++tries < 300) return setTimeout(wait, 30);
      return report('page hooks never appeared');
    }
    ['asleep', 'idle', 'listening', 'thinking', 'speaking', 'you']
      .forEach(function (s) {
        window.__setState(s);
        snap(s);
      });
    // Her voice on the light, without changing which state it is.
    window.__setState('speaking');
    window.__setAmplitude(0.9);
    after(250).then(function () {
      snap('speaking-loud');
      window.__setState('idle');
      snap('after-idle');
      report('ok');
    });
  })();
})();
