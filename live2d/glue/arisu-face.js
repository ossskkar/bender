// Arisu's face state for Live2D — which expression, and whether her eyes are shut.
//
// The same five states the portrait renderer uses, so the two faces stay
// interchangeable: idle, listening, thinking, speaking, asleep.
//
// The mouth is NOT here. Lip sync is its own module and its own contract; this
// one only picks an expression and, when she is asleep, holds her eyes closed.
//
// Blink, breath, idle motion and physics need nothing from us — the Cubism SDK
// already runs all four. Measured on Natori: two blinks in twelve seconds, with
// head angle, body angle and breath all moving continuously.

(function () {
  'use strict';

  // Natori's expressions, chosen by reading each .exp3.json rather than by name.
  // Every one of them writes ParamEyeLOpen and ParamMouthOpenY as Add 0, so an
  // expression can never fight the blink or the lip sync. That is what makes
  // this layer safe to stack on top of the other two.
  //
  // The traps in that file, and why the obvious picks are not used:
  //   Smile   closes the eyes (ParamEyeLOpen Add -1) into happy crescents. It is
  //           the classic look, but a listening face with its eyes shut is wrong.
  //   Sad     and Angry both pull ParamMouthForm hard negative, which reshapes a
  //           mouth that lip sync is simultaneously opening. Kept out of the
  //           speaking path for that reason.
  var EXPRESSION = {
    idle:      'Normal',   // literally no parameter changes at all
    listening: 'exp_02',   // brows up, faint smile, eyes open and attentive
    thinking:  'exp_04',   // brows raised and drawn in, mouth small
    speaking:  'Normal',   // the mouth is carrying it; nothing should touch MouthForm
    asleep:    'exp_05'    // relaxed brows, soft mouth; the eyes are forced below
  };

  // Asleep holds the eyes shut outright rather than trusting the expression.
  // exp_05 does close them, but so does the blink updater on its own schedule,
  // and two things writing one parameter is how you get a sleeping face that
  // flutters its eyelids.
  var EYES_SHUT = { asleep: 0 };

  var state = 'idle';
  var pending = EXPRESSION.idle;   // applied on the next frame, once

  window.ArisuFace = {
    states: Object.keys(EXPRESSION),

    setState: function (name) {
      if (!EXPRESSION[name]) return false;
      if (name === state) return true;
      state = name;
      pending = EXPRESSION[name];
      return true;
    },

    state: function () { return state; },

    // Returns an expression name exactly once per change, so the model is not
    // restarting the same expression motion on every frame.
    takePendingExpression: function () {
      var p = pending; pending = null; return p;
    },

    // null means "leave the eyes to the blink updater".
    eyeOverride: function () {
      return EYES_SHUT[state] === undefined ? null : EYES_SHUT[state];
    },

    // Escape hatch: any expression by name, including the eight the state map
    // does not use. Transient reactions go through here and then refresh().
    setExpression: function (name) { pending = name; },

    // Re-apply the current state's expression. setState() returns early when the
    // state has not changed, so a transient reaction needs this to get back.
    refresh: function () { pending = EXPRESSION[state]; }
  };
})();
