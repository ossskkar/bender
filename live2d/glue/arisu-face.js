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
    // The four that shipped no expressions, given hand-written ones instead --
    // glue/expressions/, written by tools/make-expressions.py and copied in by
    // patch-sdk.sh. Their tables below name those files.
    //
    // They are not all the same kind of face, and the tables say so rather than
    // pretending otherwise. Rice has eyes and a head and nothing else: no mouth,
    // no brows. Mark has brows and a mouth that opens but no mouth shape, so he
    // cannot smile -- his amusement is in the eyes. Wanko names its parameters
    // the old way (PARAM_EYE_L_OPEN) and has ears, which is why the one sample
    // with ears is the one whose surprise moves them.
    Hiyori: {
      states:    { idle: 'exp_idle', listening: 'exp_listening',
                   thinking: 'exp_thinking', speaking: 'exp_speaking',
                   asleep: 'exp_asleep' },
      reactions: { surprise: 'exp_surprised', amused: 'exp_amused',
                   confused: 'exp_confused', error: 'exp_sad' }
    },
    // No idle and no speaking entry: this rig has no mouth and no brows, and
    // everything left (eyes, gaze, head) is already saying something in those
    // two states. Silence is the honest expression for "nothing in particular".
    Rice: {
      states:    { listening: 'exp_listening', thinking: 'exp_thinking',
                   asleep: 'exp_asleep' },
      reactions: { surprise: 'exp_surprised', amused: 'exp_amused',
                   confused: 'exp_confused', error: 'exp_sad' }
    },
    Mark: {
      states:    { idle: 'exp_idle', listening: 'exp_listening',
                   thinking: 'exp_thinking', speaking: 'exp_idle',
                   asleep: 'exp_asleep' },
      reactions: { surprise: 'exp_surprised', amused: 'exp_amused',
                   confused: 'exp_confused', error: 'exp_sad' }
    },
    Wanko: {
      states:    { idle: 'exp_idle', listening: 'exp_listening',
                   thinking: 'exp_thinking', speaking: 'exp_speaking',
                   asleep: 'exp_asleep' },
      reactions: { surprise: 'exp_surprised', amused: 'exp_amused',
                   confused: 'exp_confused', error: 'exp_sad' }
    }
  };

  // Which rigs have a body gesture to spend. Every sample declares an Idle group
  // and -- except Mark -- a TapBody one; the group names are the SDK's own
  // (lappdefine.ts), so this is a capability list rather than a naming choice.
  // Mark ships six idle motions and no TapBody at all, so on him a gesture
  // request is a no-op, which is what the empty entry says.
  var GESTURE_GROUP = {
    Natori: 'TapBody', Haru: 'TapBody', Mao: 'TapBody', Ren: 'TapBody',
    Hiyori: 'TapBody', Rice: 'TapBody', Wanko: 'TapBody',
    Mark: ''
  };

  // PriorityForce (3), on the SDK's own scale: PriorityNone 0, PriorityIdle 1,
  // PriorityNormal 2, PriorityForce 3.
  //
  // Measured, not chosen. At PriorityNormal the request was refused: the queue
  // answered -1 with `_currentPriority` already 2, so `reserveMotion(2)` lost to
  // a motion holding the same level -- and a gesture that silently does nothing
  // is worse than no gesture at all. Force is the level the SDK itself uses for
  // a motion the user just asked for: LAppModel.startMotion() calls
  // setReservePriority(3) for it and skips the reserve check entirely, which is
  // what a tap on a rig already does. A gesture is the same kind of thing.
  //
  // What does NOT change at force: idle still resumes by itself. When the
  // gesture ends, LAppModel.update() sees isFinished() and starts an idle motion
  // again -- so nothing here needs a timer or a per-frame driver. The note this
  // replaces said a TapBody motion "would fight the idle motion queue": true of
  // driving one by hand every frame, and true of asking for one at Normal, which
  // is what the first measurement here found.
  var GESTURE_PRIORITY = 3;

  var STATES = ['idle', 'listening', 'thinking', 'speaking', 'asleep'];

  var wanted = new URLSearchParams(window.location.search).get('model');
  var MODEL = TABLES[wanted] ? wanted : 'Natori';

  // The scene may override the table for any model -- which expression a rig
  // uses for which state is a taste question, and some rigs have expressions
  // the audit kept out of the stock path for a good reason that a particular
  // scene may still want. Overrides merge over the defaults rather than
  // replacing them, so a scene can name one state and leave the rest alone.
  //
  // Resolved on every question rather than cached at load: the settings panel
  // changes expressions on a live page, and a table captured here would ignore
  // it until a reload. ArisuScene is a separate classic script and loads first;
  // with it absent the stock table stands, which is what the harness wants.
  // Declared before table(), which may return it on the very first call.
  var EMPTY = { states: {}, reactions: {} };

  function table() {
    if (window.ArisuScene && window.ArisuScene.expressions) {
      return window.ArisuScene.expressions(TABLES)[MODEL] || EMPTY;
    }
    return TABLES[MODEL] || EMPTY;
  }

  function expressionFor(s) { return table().states[s] || null; }
  function reactionFor(s) { return table().reactions[s] || null; }

  // Asleep holds the eyes shut outright rather than trusting the expression.
  // exp_05 does close them, but so does the blink updater on its own schedule,
  // and two things writing one parameter is how you get a sleeping face that
  // flutters its eyelids.
  var EYES_SHUT = { asleep: 0 };

  var state = 'idle';
  var pending = expressionFor('idle');   // applied on the next frame, once
  var pendingMotion = null;              // the same contract, for a body gesture

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
    reaction: function (name) { return reactionFor(name); },

    // Escape hatch: any expression by name, including the ones the state map
    // does not use. Transient reactions go through here and then refresh().
    setExpression: function (name) { pending = name; },

    // Re-apply the current state's expression. setState() returns early when the
    // state has not changed, so a transient reaction needs this to get back.
    refresh: function () { pending = expressionFor(state); },

    // --- body gestures ---------------------------------------------------------
    //
    // The face module owns capability, the caller owns timing: this answers "can
    // this rig gesture at all" and parks a request, and how often one is worth
    // asking for is a taste question that belongs with the avatar (a state is
    // not an occasion -- see arisu-avatar.js).
    gestureGroup: function () { return GESTURE_GROUP[MODEL] || ''; },

    canGesture: function () { return !!GESTURE_GROUP[MODEL]; },

    // Ask for a gesture, or a no-op on a rig without one. The delegate picks a
    // random motion from the group, which is what the group is for: the samples
    // ship several and repeating one is what makes a rig look looped.
    //
    // `tries` is the part that makes this work at all. The delegate answers -1
    // while the rig's motions are still being preloaded -- the sample starts the
    // file load and returns "cannot start" in the same breath -- so the first ask
    // of a page's life is routinely refused, and a gesture asked for once and
    // dropped would simply never play. The budget is small on purpose: eight
    // frames is a fifth of a second, long after which something else is wrong.
    gesture: function () {
      if (!GESTURE_GROUP[MODEL]) return false;
      pendingMotion = { group: GESTURE_GROUP[MODEL], priority: GESTURE_PRIORITY,
                        tries: 8 };
      return true;
    },

    // The delegate could not start it *this frame*: park it again for the next
    // one, and give up quietly once the budget is spent. Called only on refusal.
    retryMotion: function (m) {
      if (!m || !(m.tries > 1)) return false;
      pendingMotion = { group: m.group, priority: m.priority, tries: m.tries - 1 };
      return true;
    },

    // Same one-shot contract as takePendingExpression(), for the same reason:
    // read every frame, acted on once.
    takePendingMotion: function () {
      var m = pendingMotion; pendingMotion = null; return m;
    }
  };
})();
