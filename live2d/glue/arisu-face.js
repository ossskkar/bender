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
//
// Seven samples ship, one table each. The model comes from the page URL
// (`?model=Haru`), set by the client from the character: Arisu wears the female
// samples, Chopper the male ones. It must match what lapplive2dmanager loads,
// which reads the same parameter and falls back to Natori the same way.

(function () {
  'use strict';

  // Expressions chosen by reading each .exp3.json rather than by name. null
  // means "no expression": Hiyori, Rice and Mark ship none, so on them only the
  // asleep eye override below changes anything.
  //
  // Natori. Every expression writes ParamEyeLOpen and ParamMouthOpenY as Add 0,
  // so an expression can never fight the blink or the lip sync. The traps:
  //   Smile   closes the eyes (ParamEyeLOpen Add -1) into happy crescents. It is
  //           the classic look, but a listening face with its eyes shut is wrong.
  //   Sad     and Angry both pull ParamMouthForm hard negative, which reshapes a
  //           mouth that lip sync is simultaneously opening. Kept out of the
  //           speaking path for that reason.
  // Haru. No neutral file: F01 is the mildest (ParamMouthForm +0.27 and nothing
  //   else), so it stands in for idle, listening and speaking. F02 and F03 add
  //   ParamMouthOpenY +1, which would hold her mouth open over the lip sync.
  // Mao. Lip sync is ParamA, which every file writes as Add 0. exp_03 is eyes
  //   shut and nothing else; exp_04 is bright eyes with a sparkle effect.
  // Ren. exp_01 is all zeros; exp_03 shuts the eyes; exp_05 is raised, drawn
  //   brows with a flat mouth.
  var TABLES = {
    Natori: {
      states:    { idle: 'Normal', listening: 'exp_02', thinking: 'exp_04',
                   speaking: 'Normal', asleep: 'exp_05' },
      reactions: { surprise: 'Surprised', amused: 'Smile', confused: 'exp_01',
                   error: 'Sad' }
    },
    Haru: {
      states:    { idle: 'F01', listening: 'F01', thinking: 'F08',
                   speaking: 'F01', asleep: 'F05' },
      reactions: { surprise: 'F06', amused: 'F05', confused: 'F08', error: 'F04' }
    },
    Mao: {
      states:    { idle: 'exp_01', listening: 'exp_04', thinking: 'exp_05',
                   speaking: 'exp_01', asleep: 'exp_03' },
      reactions: { surprise: 'exp_07', amused: 'exp_02', confused: 'exp_05',
                   error: 'exp_08' }
    },
    Ren: {
      states:    { idle: 'exp_01', listening: 'exp_01', thinking: 'exp_05',
                   speaking: 'exp_01', asleep: 'exp_03' },
      reactions: { amused: 'exp_02', confused: 'exp_05', error: 'exp_04' }
    },
    Hiyori: { states: {}, reactions: {} },
    Rice:   { states: {}, reactions: {} },
    Mark:   { states: {}, reactions: {} },
    Wanko:  { states: {}, reactions: {} }
  };

  var STATES = ['idle', 'listening', 'thinking', 'speaking', 'asleep'];

  var wanted = new URLSearchParams(window.location.search).get('model');
  var MODEL = TABLES[wanted] ? wanted : 'Natori';
  var TABLE = TABLES[MODEL];

  function expressionFor(s) { return TABLE.states[s] || null; }

  // Asleep holds the eyes shut outright rather than trusting the expression.
  // exp_05 does close them, but so does the blink updater on its own schedule,
  // and two things writing one parameter is how you get a sleeping face that
  // flutters its eyelids.
  var EYES_SHUT = { asleep: 0 };

  var state = 'idle';
  var pending = expressionFor('idle');   // applied on the next frame, once

  window.ArisuFace = {
    model: MODEL,
    states: STATES,

    setState: function (name) {
      if (STATES.indexOf(name) < 0) return false;
      if (name === state) return true;
      state = name;
      pending = expressionFor(name);
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

    // This model's expression for a transient reaction, or null when the rig
    // has nothing that reads as it.
    reaction: function (name) { return TABLE.reactions[name] || null; },

    // Escape hatch: any expression by name, including the ones the state map
    // does not use. Transient reactions go through here and then refresh().
    setExpression: function (name) { pending = name; },

    // Re-apply the current state's expression. setState() returns early when the
    // state has not changed, so a transient reaction needs this to get back.
    refresh: function () { pending = expressionFor(state); }
  };
})();
