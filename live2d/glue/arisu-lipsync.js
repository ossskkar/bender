// Arisu lip-sync for Live2D — amplitude source only.
//
// This is deliberately the SAME math as faces/renderer.js, because that math is
// already proven against her real voice. The only new thing here is the output:
// a single 0..1 number that the Cubism model applies to ParamMouthOpenY.
//
// The contract with the rest of Arisu is narrow on purpose:
//   audio  ->  amplitude  ->  ParamMouthOpenY
// Nothing in this file knows about Live2D, and nothing in Live2D knows about
// her voice loop.
//
// Lesson carried over from the app's lip sync: tap her OUTPUT stream, never the
// microphone. The mic hears the room, echoes her back late, and hears you
// talking over her. attachStream()/attachAudio() are the real paths; useMic()
// exists only to test the analyser without the voice loop running.
//
// Loaded as a classic script, before the module bundle. Exposes window.ArisuLipSync.

(function () {
  'use strict';

  // Band weights and smoothing lifted verbatim from faces/renderer.js.
  var FFT_SIZE = 1024;
  // Lower than the portrait renderer's 0.55. That value smooths a glow, which
  // wants to look continuous; a jaw wants the gaps between syllables to survive.
  var SMOOTHING = 0.2;
  var LO_FROM = 2, LO_TO = 22;     // 20 bins of low/voiced energy
  var HI_FROM = 22, HI_TO = 120;   // 98 bins of upper formants
  var LO_GAIN = 1.6, HI_GAIN = 1.1;
  // Auto-gain. The portrait renderer feeds a glow, where clipping is invisible;
  // a jaw clamps at 1.0 and just hangs open. Measured against a real sample wav,
  // the raw band energy pins at 1.0 for most of an utterance, so the mouth must
  // be normalised against a running peak instead of a fixed gain -- which also
  // means it adapts to whatever level her TTS actually comes out at.
  var PEAK_FLOOR = 0.45;           // never amplify quiet-room noise into speech
  var PEAK_RELEASE = 0.9992;       // peak decays over a few seconds
  // Where the mouth counts as shut, as a fraction of the running peak. Measured
  // on a real speech clip: band energy runs about 0.87 at its quietest against a
  // 1.74 peak, so half the peak is very close to the actual floor of speech --
  // and unlike a tracked minimum it converges the instant the peak does.
  var FLOOR_RATIO = 0.5;
  var NOISE_GATE = 0.02;           // below this, the mouth is shut
  var ATTACK = 0.5;                // jaw opens fast
  var RELEASE = 0.25;              // and closes slower, but not sluggishly
  var JAW_CURVE = 1.0;             // pow(): the expander already sets the shape
  var HOST_TIMEOUT_MS = 150;       // host stopped feeding -> let the jaw close

  var actx = null;
  var analyser = null;
  var freq = null;
  var live = false;         // an analyser is connected to something
  var micStream = null;
  var micOn = false;
  var amp = 0;              // raw, this frame
  var ampS = 0;             // smoothed, what the mouth actually follows
  var lastAmpAt = 0;        // for the host-feed path
  var hostFed = false;
  var speech = null;        // synthetic envelope, test only
  var peak = PEAK_FLOOR;    // running loud reference for the expander
  var autoGain = true;

  function ensureCtx() {
    if (!actx) actx = new (window.AudioContext || window.webkitAudioContext)();
    if (actx.state === 'suspended') actx.resume();
    if (!analyser) {
      analyser = actx.createAnalyser();
      analyser.fftSize = FFT_SIZE;
      analyser.smoothingTimeConstant = SMOOTHING;
      freq = new Uint8Array(analyser.frequencyBinCount);
    }
    return actx;
  }

  function readAnalyser() {
    analyser.getByteFrequencyData(freq);
    var lo = 0, hi = 0, i;
    for (i = LO_FROM; i < LO_TO; i++) lo += freq[i];
    for (i = HI_FROM; i < HI_TO; i++) hi += freq[i];
    lo /= (LO_TO - LO_FROM) * 255;
    hi /= (HI_TO - HI_FROM) * 255;
    var raw = lo * LO_GAIN + hi * HI_GAIN;

    if (!autoGain) return Math.min(1, raw);

    // An expander, not just a gain. Dividing by the peak alone still leaves
    // continuous speech sitting near 1.0, because the quiet level of speech is
    // nowhere near zero -- the mouth hangs open and merely wobbles. Mapping the
    // top half of the range onto 0..1 is what makes the jaw actually close
    // between syllables.
    if (raw > peak) peak = raw;                              // instant attack
    else peak = Math.max(PEAK_FLOOR, peak * PEAK_RELEASE);   // slow release

    if (raw < NOISE_GATE) return 0;
    var floor = peak * FLOOR_RATIO;
    return Math.max(0, Math.min(1, (raw - floor) / (peak - floor)));
  }

  function readSpeech(now) {
    var st = now / 1000 - speech.start;
    if (st > speech.end) { speech = null; return 0; }
    var a = 0;
    for (var i = 0; i < speech.seq.length; i++) {
      var b = speech.seq[i][0], e = speech.seq[i][1], v = speech.seq[i][2];
      if (st >= b && st <= e) {
        var k = (st - b) / (e - b);
        a = v * Math.pow(Math.sin(Math.PI * k), 0.7);
      }
    }
    return a;
  }

  // Called once per rendered frame by the model. Advances the smoothing, so it
  // must not be called twice in a frame or the jaw moves at double speed.
  function value() {
    var now = (typeof performance !== 'undefined' ? performance.now() : Date.now());

    if (live && analyser) {
      amp = readAnalyser();
    } else if (speech) {
      amp = readSpeech(now);
    } else if (hostFed && now - lastAmpAt > HOST_TIMEOUT_MS) {
      // The host went quiet mid-utterance. Decay rather than freeze the mouth
      // open, which is the failure everyone notices.
      amp *= 0.86;
      if (amp < 0.004) { amp = 0; hostFed = false; }
    }

    ampS += (amp - ampS) * (amp > ampS ? ATTACK : RELEASE);
    if (ampS < 0.0005) ampS = 0;
    return Math.pow(ampS, JAW_CURVE);
  }

  window.ArisuLipSync = {
    value: value,

    // Raw amplitude already computed elsewhere (native host, server, WebRTC
    // stats). 0..1. Keep calling it while she speaks; stopping closes the mouth.
    setAmplitude: function (v) {
      amp = Math.max(0, Math.min(1, v || 0));
      lastAmpAt = (typeof performance !== 'undefined' ? performance.now() : Date.now());
      hostFed = true;
      live = false;
      speech = null;
    },

    // Her output <audio>/<video> element. Same call as the portrait renderer.
    //
    // The analyser is a TAP, never a link in the audible path -- the source
    // fans out to both. Routing sound *through* the analyser to the speakers is
    // what made the microphone howl: the mic reached the destination through a
    // connection that only the playback path ever needed.
    attachAudio: function (el) {
      var ac = ensureCtx();
      var src = ac.createMediaElementSource(el);
      src.connect(analyser);        // tap, goes nowhere
      src.connect(ac.destination);  // audible path
      live = true;
      speech = null;
      return true;
    },

    // Her WebRTC output track. This is the path the browser client uses.
    attachStream: function (stream) {
      var ac = ensureCtx();
      ac.createMediaStreamSource(stream).connect(analyser);
      // Tap only. The <audio> element already plays the remote track; adding a
      // second path here would double her volume.
      live = true;
      speech = null;
      return true;
    },

    detach: function () {
      live = false;
      peak = PEAK_FLOOR;
      speech = null;
      hostFed = false;
      amp = 0;
    },

    // Test only. The mic is the wrong source for a talking avatar.
    useMic: function () {
      if (micOn) {
        micOn = false; live = false; amp = 0;
        if (micStream) micStream.getTracks().forEach(function (t) { t.stop(); });
        micStream = null;
        return Promise.resolve(false);
      }
      return navigator.mediaDevices.getUserMedia({
        // Echo cancellation matters even with the graph fixed: the speakers are
        // a few centimetres from the microphone on a tablet.
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: false }
      }).then(function (st) {
        var ac = ensureCtx();
        // Tap only. Never to destination -- that is a feedback loop, not a test.
        ac.createMediaStreamSource(st).connect(analyser);
        micStream = st; micOn = true; live = true; speech = null;
        return true;
      });
    },

    // Synthetic babble envelope. Proves the parameter is wired without needing
    // audio permission or the voice loop. Same generator as renderer.js.
    speakDemo: function (seconds) {
      var dur = seconds || 4.6;
      var seq = [], t = 0;
      while (t < dur) {
        var d = 0.07 + Math.random() * 0.13;
        seq.push([t, t + d, 0.35 + Math.random() * 0.65]);
        t += d + (Math.random() < 0.18 ? 0.16 + Math.random() * 0.2
                                       : 0.02 + Math.random() * 0.05);
      }
      live = false; hostFed = false;
      speech = { start: (typeof performance !== 'undefined' ? performance.now() : Date.now()) / 1000,
                 seq: seq, end: t + 0.3 };
    },

    // Off means a fixed gain, which clips. On by default; the knob exists so a
    // host already sending normalised amplitude is not normalised twice.
    setAutoGain: function (on) { autoGain = !!on; peak = PEAK_FLOOR; },
    levels: function () { return { peak: peak, floor: peak * FLOOR_RATIO }; },

    isLive: function () { return live || !!speech || hostFed; },
    isMicOn: function () { return micOn; }
  };
})();
