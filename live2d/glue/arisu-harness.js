// Test overlay for the lip-sync prototype. Not part of Arisu — delete this file
// and its script tag once she drives the mouth from her own voice loop.
//
// Three buttons, each proving a different link in the chain:
//   demo  — synthetic envelope. Proves ParamMouthOpenY is wired at all.
//   wav   — a real audio file through attachAudio(). Proves the analyser math.
//   mic   — the microphone. Proves live stream capture. Wrong source for real use.
//
// Also prints the live amplitude, so a dead mouth can be told apart from a dead
// analyser without opening the console.

(function () {
  'use strict';

  var WAV = 'Resources/Haru/sounds/haru_talk_13.wav';

  function build() {
    var L = window.ArisuLipSync;
    if (!L) return;

    var bar = document.createElement('div');
    bar.style.cssText = [
      'position:fixed', 'left:12px', 'top:12px', 'z-index:9999',
      'display:flex', 'gap:6px', 'align-items:center',
      'font:12px/1.4 -apple-system,system-ui,sans-serif',
      'color:#fff', 'background:rgba(18,18,22,0.72)',
      'padding:8px 10px', 'border-radius:10px',
      '-webkit-backdrop-filter:blur(8px)', 'backdrop-filter:blur(8px)'
    ].join(';');

    function btn(label, fn) {
      var b = document.createElement('button');
      b.textContent = label;
      b.style.cssText = [
        'font:inherit', 'color:#fff', 'background:rgba(255,255,255,0.08)',
        'border:1px solid rgba(255,255,255,0.18)', 'border-radius:7px',
        'padding:5px 10px', 'cursor:pointer', 'touch-action:manipulation'
      ].join(';');
      b.onclick = function (e) { e.stopPropagation(); fn(b); };
      bar.appendChild(b);
      return b;
    }

    btn('demo', function () { L.speakDemo(); });

    var audio = null;
    btn('wav', function () {
      if (!audio) {
        audio = new Audio(WAV);
        audio.crossOrigin = 'anonymous';
        L.attachAudio(audio);          // one MediaElementSource per element, ever
        audio.onended = function () { L.detach(); };
      }
      audio.currentTime = 0;
      audio.play();
    });

    var mic = btn('mic', function (b) {
      Promise.resolve(L.useMic()).then(function (on) {
        b.style.color = on ? '#7de3ff' : '#fff';
      });
    });

    var meter = document.createElement('div');
    meter.style.cssText = 'width:90px;height:6px;border-radius:3px;background:rgba(255,255,255,0.14);overflow:hidden';
    var fill = document.createElement('div');
    fill.style.cssText = 'height:100%;width:0%;background:linear-gradient(90deg,#ff3d8b,#7de3ff)';
    meter.appendChild(fill);
    bar.appendChild(meter);

    var num = document.createElement('span');
    num.style.cssText = 'min-width:34px;opacity:0.75;font-variant-numeric:tabular-nums';
    num.textContent = '0.00';
    bar.appendChild(num);

    document.body.appendChild(bar);

    // Read-only mirror. value() advances smoothing, so the meter must NOT call
    // it — it reads what the model last applied instead.
    setInterval(function () {
      var v = window.__arisuMouth || 0;
      fill.style.width = (v * 100).toFixed(1) + '%';
      num.textContent = v.toFixed(2);
    }, 60);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', build);
  } else {
    build();
  }
})();
