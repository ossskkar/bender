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

  // Reactions come from the model's own table in arisu-face.js. Anything a rig
  // cannot express is left out rather than approximated -- a wrong face is
  // worse than no change.
  //
  //   nod is still missing, and for a narrower reason than before. It used to
  //   say faking a nod with a TapBody motion "would fight the idle motion queue".
  //   That part is answered: a gesture now goes through the queue at
  //   PriorityNormal, which interrupts idle and lets the delegate restart it.
  //   What is left is that no sample ships a head motion at all -- TapBody is
  //   the body -- so a "nod" would still be a lie about what she is doing.
  //
  // Gestures are asked for at occasions, never at states. A state lasts minutes
  // and a gesture is two seconds: firing one on every idle->listening flip would
  // make her twitch through a conversation, which is the thing this file exists
  // to avoid. Two occasions earn one: waking up, and laughing.

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
        // Coming back is a body thing as well as a face one. On a rig with no
        // gesture group this is false and nothing happens, which is the point of
        // asking the face module rather than the model.
        F.gesture();
        return true;
      }
      var expression = F.reaction(name);
      if (expression) {
        // A laugh is not only a face either -- the samples' body motions are
        // what "amused" looks like from the shoulders down.
        if (name === 'amused') F.gesture();
        transient(expression);
        return true;
      }
      return false;
    },

    speakDemo: function () { F.setState('speaking'); L.speakDemo(); },
    attachAudio: function (el) { return L.attachAudio(el); },
    useMic: function () { return L.useMic(); },

    // The test overlay is the only panel here. Harmless when it is not loaded,
    // which is the point -- the caller should never have to check.
    showPanel: function (v) {
      // Not .hidden -- the bar carries an inline display:flex, which outranks
      // the user agent's [hidden]{display:none} and left this a silent no-op.
      var bar = document.getElementById('arisu-harness');
      if (bar) bar.style.display = v ? 'flex' : 'none';
    }
  };
})();
