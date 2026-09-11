// The `window.avatar` contract, on top of Live2D.
//
// This is the whole point of the prototype. Her browser client and her iOS app
// both drive a face page the same way -- `face.contentWindow.avatar.setState()`
// and `.setAmplitude()` -- and neither of them knows or cares what is drawing.
// Match that interface and the Live2D page becomes a drop-in third face beside
// arisu.html and chopper.html, with nothing on the calling side to change.
//
// Kept identical to the portrait renderer's surface in faces/renderer.js, down
// to the no-op members, so a page can be swapped in without anyone checking
// first whether a method exists.

(function () {
  'use strict';

  var L = window.ArisuLipSync;
  var F = window.ArisuFace;
  if (!L || !F) return;

  // Cubism cross-fades an expression in over ~880ms and out over another ~880ms
  // (measured on Natori, ParamMouthForm 0 to -3 and back). A reaction shorter
  // than about two seconds therefore starts reverting before it has fully
  // arrived, and reads as a twitch rather than a face.
  var REACTION_MS = 2200;
  var revertTimer = null;

  // Reactions the rig can actually express. Anything not here is deliberately
  // left out rather than approximated -- a wrong face is worse than no change.
  //   nod is missing on purpose: it is a head movement, not an expression, and
  //   faking it with Natori's TapBody motions would fight the idle motion queue.
  var REACTION = {
    surprise:  'Surprised',
    amused:    'Smile',      // closes the eyes into crescents -- right, here
    confused:  'exp_01',
    error:     'Sad'
  };

  function transient(expression) {
    F.setExpression(expression);
    clearTimeout(revertTimer);
    revertTimer = setTimeout(function () { F.refresh(); }, REACTION_MS);
  }

  window.avatar = {
    setState: function (s) { return F.setState(s); },

    // The host asserts a mouth opening, 0..1, so it is passed straight through.
    // It is deliberately NOT run through the lip-sync expander: the browser
    // client injects a synthetic 0.10-0.26 envelope when Safari hands back a
    // silent analyser, and expanding those against a peak would floor them to
    // zero -- freezing the mouth in exactly the case that workaround exists for.
    setAmplitude: function (v) { L.setAmplitude(v); },

    react: function (name) {
      if (name === 'sleep') return F.setState('asleep');
      if (name === 'thinking') return F.setState('thinking');
      if (name === 'wake') {
        if (F.state() === 'asleep') F.setState('idle');
        return true;
      }
      if (REACTION[name]) { transient(REACTION[name]); return true; }
      return false;
    },

    speakDemo: function () { F.setState('speaking'); L.speakDemo(); },
    attachAudio: function (el) { return L.attachAudio(el); },
    useMic: function () { return L.useMic(); },

    // The test overlay is the only panel here. Harmless when it is not loaded,
    // which is the point -- the caller should never have to check.
    showPanel: function (v) {
      var bar = document.getElementById('arisu-harness');
      if (bar) bar.hidden = !v;
    }
  };
})();
