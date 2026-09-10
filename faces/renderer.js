
// Every character is a different face, so the landmarks are data. The values
// this renderer shipped with are the fallbacks, which are also Arisu's -- hers
// is the portrait it was authored against. See faces/<id>.json.
//
// The two scales exist because the iris and the mouth glow were sized as flat
// fractions of the frame width, which is only right for a face whose eyes are
// as far apart as this one's. On a face with eyes half as far apart they draw
// saucers. Scaling them off the eye spacing keeps them in proportion.
const F = (typeof window !== 'undefined' && window.CHARACTER_FACE) || {};
const BW = F.bw || 300, BH = F.bh || 314;
const EYE_L = F.eyeL || [0.375, 0.470], EYE_R = F.eyeR || [0.674, 0.468];
const MOUTH = F.mouth || [0.512, 0.672];
const EYE_SCALE = F.eyeScale == null ? 1 : F.eyeScale;
const MOUTH_SCALE = F.mouthScale == null ? 1 : F.mouthScale;
const FACE_JAW = F.jaw == null ? 0.66 : F.jaw;

// 8x8 ordered (Bayer) dither — temporally stable, so the plate doesn't crawl
const BAYER = new Float32Array([
   0,32, 8,40, 2,34,10,42, 48,16,56,24,50,18,58,26,
  12,44, 4,36,14,46, 6,38, 60,28,52,20,62,30,54,22,
   3,35,11,43, 1,33, 9,41, 51,19,59,27,49,17,57,25,
  15,47, 7,39,13,45, 5,37, 63,31,55,23,61,29,53,21
].map((v) => (v + 0.5) / 64));
const PAPER = [233, 230, 221], INK = [24, 23, 26], GHOST = [199, 197, 189];

const PALETTES = {
  'Neon Bloom': [[0,[2,1,8]],[0.20,[26,5,44]],[0.42,[112,18,104]],[0.60,[232,52,140]],[0.76,[255,124,172]],[0.90,[176,228,255]],[1,[255,255,255]]],
  'Cold Signal': [[0,[1,3,6]],[0.28,[9,30,42]],[0.54,[28,106,136]],[0.76,[118,216,238]],[1,[255,255,255]]],
  'Ember': [[0,[6,2,2]],[0.28,[46,10,6]],[0.54,[158,44,20]],[0.78,[255,140,60]],[1,[255,242,214]]]
};

function buildLUT(stops) {
  const lut = new Float32Array(768);
  for (let i = 0; i < 256; i++) {
    const t = i / 255;
    let a = stops[0], b = stops[stops.length - 1];
    for (let s = 0; s < stops.length - 1; s++) {
      if (t >= stops[s][0] && t <= stops[s + 1][0]) { a = stops[s]; b = stops[s + 1]; break; }
    }
    const span = b[0] - a[0] || 1, k = (t - a[0]) / span;
    lut[i * 3] = a[1][0] + (b[1][0] - a[1][0]) * k;
    lut[i * 3 + 1] = a[1][1] + (b[1][1] - a[1][1]) * k;
    lut[i * 3 + 2] = a[1][2] + (b[1][2] - a[1][2]) * k;
  }
  return lut;
}

const STATE_MIX = {
  idle:      { neon: 0.72, cold: 0.28, ember: 0, intensity: 1.02, spacing: 1,    glitch: 0.10, open: 1,    bloom: 1 },
  listening: { neon: 0.34, cold: 0.66, ember: 0, intensity: 1.00, spacing: 0.9,  glitch: 0.06, open: 1.12, bloom: 1.12 },
  thinking:  { neon: 0.52, cold: 0.48, ember: 0, intensity: 0.88, spacing: 0.72, glitch: 0.34, open: 0.82, bloom: 0.86 },
  speaking:  { neon: 0.92, cold: 0.08, ember: 0, intensity: 1.10, spacing: 1.06, glitch: 0.13, open: 1,    bloom: 1.3 },
  asleep:    { neon: 0.42, cold: 0.58, ember: 0, intensity: 0.42, spacing: 1.7,  glitch: 0.03, open: 0.04, bloom: 0.6 }
};

class Component extends DCLogic {
  constructor(p) {
    super(p);
    this.canvasRef = React.createRef();
    this.stageRef = React.createRef();
    this.srcRef = React.createRef();
    this.panelRef = React.createRef();
    this.stateRef = React.createRef();
    this.ampRef = React.createRef();
    this.dotRef = React.createRef();
    this.micRef = React.createRef();
    this.luts = {
      neon: buildLUT(PALETTES['Neon Bloom']),
      cold: buildLUT(PALETTES['Cold Signal']),
      ember: buildLUT(PALETTES['Ember'])
    };
    this.work = new Uint8Array(768);
    this.s = {
      state: 'idle', amp: 0, ampS: 0,
      mix: Object.assign({}, STATE_MIX.idle),
      tilt: 0, tiltT: 0, nod: 0, nodT: 0, sway: 0,
      eyeOpen: 1, eyeOpenT: 1, eyeWide: 0, squint: 0,
      gazeX: 0, gazeY: 0, gazeTX: 0, gazeTY: 0,
      blinkAt: 2200, tear: 0, sweep: -1, flash: 0, wobble: 0,
      lastSacc: 0, boot: 0
    };
    this.ready = false;
    this.panelHidden = false;
  }

  componentDidMount() {
    const cv = this.canvasRef.current;
    this.ctx = cv.getContext('2d');
    this.buf = document.createElement('canvas');
    this.buf.width = BW; this.buf.height = BH;
    this.bctx = this.buf.getContext('2d');
    this.comp = document.createElement('canvas'); this.comp.width = BW; this.comp.height = BH;
    this.cctx = this.comp.getContext('2d');
    this.g1 = document.createElement('canvas'); this.g1.width = BW >> 1; this.g1.height = BH >> 1;
    this.g1ctx = this.g1.getContext('2d');
    this.g2 = document.createElement('canvas'); this.g2.width = BW >> 3; this.g2.height = BH >> 3;
    this.g2ctx = this.g2.getContext('2d');
    this.img = this.bctx.createImageData(BW, BH);
    for (let i = 3; i < this.img.data.length; i += 4) this.img.data[i] = 255;

    this.noise = new Float32Array(BW * BH);
    for (let i = 0; i < this.noise.length; i++) this.noise[i] = Math.random();

    this.onResize = () => this.resize();
    window.addEventListener('resize', this.onResize);
    this.resize();

    const im = this.srcRef.current || new Image();
    const take = () => { this.sample(im); this.ready = true; };
    if (im.complete && im.naturalWidth) take();
    else { im.onload = take; if (!im.src) im.src = 'assets/portrait.png'; }

    this.onKey = (e) => {
      const k = e.key.toLowerCase();
      const map = { '1': 'idle', '2': 'listening', '3': 'thinking', '4': 'speaking', '5': 'asleep' };
      if (map[k]) this.setAvatarState(map[k]);
      if (k === 'h') this.togglePanel();
      if (k === ' ') { e.preventDefault(); this.speakDemo(); }
    };
    window.addEventListener('keydown', this.onKey);

    this.api = {
      setState: (s) => this.setAvatarState(s),
      setAmplitude: (v) => {
        this.s.amp = Math.max(0, Math.min(1, v || 0));
        this.lastAmpAt = performance.now();
      },
      react: (r) => this.react(r),
      speakDemo: () => this.speakDemo(),
      attachAudio: (el) => this.attachAudio(el),
      useMic: () => this.mic(),
      showPanel: (v) => this.togglePanel(!v)
    };
    window.avatar = this.api;
    // synchronous frame stepper, for testing in environments with throttled timers
    window.avatarStep = (n, dt) => {
      for (let i = 0; i < (n || 1); i++) {
        this._dbg = (this._dbg || 0) + (dt || 16);
        this.frame(this._dbg / 1000, performance.now() + this._dbg);
      }
    };

    this.t0 = performance.now();
    this.lastDraw = 0;
    this.loop = (now) => {
      const cap = this.props.fpsCap || 60;
      if (now - this.lastDraw >= 1000 / cap - 1.5) {
        this.lastDraw = now;
        this.frame((now - this.t0) / 1000, now);
      }
      this.raf = requestAnimationFrame(this.loop);
    };
    this.raf = requestAnimationFrame(this.loop);
    // fallback driver for webviews that throttle rAF (background tabs, some embeds)
    this.watchdog = setInterval(() => {
      const now = performance.now();
      if (now - this.lastDraw > 60) {
        this.lastDraw = now;
        this.frame((now - this.t0) / 1000, now);
      }
    }, 30);
    this.markState();
  }

  componentWillUnmount() {
    cancelAnimationFrame(this.raf);
    clearInterval(this.watchdog);
    window.removeEventListener('resize', this.onResize);
    window.removeEventListener('keydown', this.onKey);
    if (this.actx) this.actx.close();
    if (window.avatar === this.api) delete window.avatar;
  }

  resize() {
    const cv = this.canvasRef.current;
    if (!cv) return;
    const r = cv.getBoundingClientRect();
    let dpr = Math.min(window.devicePixelRatio || 1, 2);
    // cap the backing store: everything is bloom-soft, so extra pixels buy nothing
    const budget = 520000;
    const area = r.width * r.height * dpr * dpr;
    if (area > budget) dpr *= Math.sqrt(budget / area);
    cv.width = Math.max(1, Math.round(r.width * dpr));
    cv.height = Math.max(1, Math.round(r.height * dpr));
    this.dpr = dpr;
  }

  sample(im) {
    const c = document.createElement('canvas');
    c.width = BW; c.height = BH;
    const cx = c.getContext('2d');
    cx.drawImage(im, 0, 0, BW, BH);
    const d = cx.getImageData(0, 0, BW, BH).data;
    const lum = new Float32Array(BW * BH);
    const raw = new Float32Array(BW * BH);
    const rgb = new Uint8ClampedArray(BW * BH * 3);
    for (let i = 0, p = 0; i < lum.length; i++, p += 4) {
      const r = d[p], g = d[p + 1], b = d[p + 2];
      const l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      raw[i] = l;
      rgb[i * 3] = r; rgb[i * 3 + 1] = g; rgb[i * 3 + 2] = b;
      const shaped = Math.pow(Math.max(0, (l - 0.10) / 0.76), 0.48);
      lum[i] = shaped > 1 ? 1 : shaped;
    }
    // Flood-fill the backdrop inward from the borders. The criterion is LOCAL
    // (each pixel within tolerance of the neighbour it spread from), so a smooth
    // studio gradient is followed all the way round while the subject's edge,
    // which steps sharply, stops the fill.
    // Gradient magnitude: the backdrop is smooth, the subject's outline is not,
    // so an edge ridge is what stops the fill from leaking into the skin.
    const grad = new Float32Array(BW * BH);
    for (let y = 1; y < BH - 1; y++) {
      for (let x = 1; x < BW - 1; x++) {
        const i = y * BW + x;
        const gx = raw[i + 1] - raw[i - 1];
        const gy = raw[i + BW] - raw[i - BW];
        grad[i] = Math.abs(gx) + Math.abs(gy);
      }
    }
    // The subject of a portrait is centred, so this region is never background —
    // a hard backstop if the fill still squeezes through a soft edge.
    const keep = new Uint8Array(BW * BH);
    for (let y = 0; y < BH; y++) {
      for (let x = 0; x < BW; x++) {
        const nx = (x / BW - 0.5) / 0.36, nyy = (y / BH - 0.54) / 0.45;
        if (nx * nx + nyy * nyy < 1) keep[y * BW + x] = 1;
      }
    }
    const mask = new Uint8Array(BW * BH);
    const tol = 0.016, edgeTol = 0.03;
    const stack = [];
    const seed = (i) => { if (!mask[i] && !keep[i]) { mask[i] = 1; stack.push(i); } };
    for (let x = 0; x < BW; x++) { seed(x); seed((BH - 1) * BW + x); }
    for (let y = 0; y < BH; y++) { seed(y * BW); seed(y * BW + BW - 1); }
    while (stack.length) {
      const i = stack.pop();
      const v = raw[i];
      const x = i % BW, y = (i - x) / BW;
      const test = (j) => {
        if (mask[j] || keep[j]) return;
        if (grad[j] > edgeTol) return;
        if (Math.abs(raw[j] - v) > tol) return;
        mask[j] = 1; stack.push(j);
      };
      if (x > 0) test(i - 1);
      if (x < BW - 1) test(i + 1);
      if (y > 0) test(i - BW);
      if (y < BH - 1) test(i + BW);
    }
    for (let i = 0; i < lum.length; i++) if (mask[i]) lum[i] = 0;
    this.bg = mask;
    this.raw = raw;
    this.rgb = rgb;
    const edge = new Float32Array(BW * BH);
    for (let y = 1; y < BH - 1; y++) {
      for (let x = 1; x < BW - 1; x++) {
        const i = y * BW + x;
        const gx = raw[i + 1] - raw[i - 1];
        const gy = raw[i + BW] - raw[i - BW];
        let m = Math.sqrt(gx * gx + gy * gy) * 1.45 - 0.085;
        edge[i] = m < 0 ? 0 : m > 1 ? 1 : m;
      }
    }
    this.edge = edge;
    // soften the silhouette edge by one ring
    const out = new Float32Array(lum);
    for (let y = 1; y < BH - 1; y++) {
      for (let x = 1; x < BW - 1; x++) {
        const i = y * BW + x;
        if (!mask[i]) continue;
        if (!mask[i - 1] || !mask[i + 1] || !mask[i - BW] || !mask[i + BW]) {
          out[i] = 0.10;
        }
      }
    }
    this.lum = out;
  }

  setAvatarState(s) {
    if (!STATE_MIX[s]) return;
    if (s === 'idle' && this.s.state === 'asleep') this.react('wake');
    this.s.state = s;
    if (s === 'thinking') this.s.sweep = 0;
    this.s.eflash = 1;
    if (s === 'asleep') this.s.eyeOpenT = 0.02;
    else if (this.s.eyeOpenT < 0.5) this.s.eyeOpenT = 1;
    this.markState();
  }

  markState() {
    if (this.stateRef.current) this.stateRef.current.textContent = this.s.state;
    const k = this.ck || { onFg: '#06060a', onBg: '#b8e8ff', offFg: 'rgba(255,255,255,0.55)', offBg: 'rgba(255,255,255,0.03)', offBd: 'rgba(255,255,255,0.12)' };
    const p = this.panelRef.current;
    if (p) p.querySelectorAll('[data-st]').forEach((b) => {
      const on = b.dataset.st === this.s.state;
      b.style.color = on ? k.onFg : k.offFg;
      b.style.background = on ? k.onBg : k.offBg;
      b.style.borderColor = on ? k.onBg : k.offBd;
    });
  }

  applyChrome(mode) {
    const eink = mode === 'E-Ink';
    this.ck = eink
      ? { onFg: '#eae7de', onBg: '#26242a', offFg: 'rgba(28,26,30,0.68)', offBg: 'rgba(28,26,30,0.045)', offBd: 'rgba(28,26,30,0.2)' }
      : { onFg: '#06060a', onBg: '#b8e8ff', offFg: 'rgba(255,255,255,0.55)', offBg: 'rgba(255,255,255,0.03)', offBd: 'rgba(255,255,255,0.12)' };
    const p = this.panelRef.current;
    if (p) {
      p.style.background = eink ? 'rgba(238,235,227,0.9)' : 'rgba(10,4,14,0.72)';
      p.style.borderColor = eink ? 'rgba(28,26,30,0.18)' : 'rgba(255,255,255,0.09)';
      p.querySelectorAll('button').forEach((b) => {
        if (b.dataset.st) return;
        const primary = b.textContent.trim() === 'speak demo';
        b.style.color = eink ? (primary ? '#eae7de' : 'rgba(28,26,30,0.66)') : (primary ? '#06060a' : 'rgba(255,255,255,0.45)');
        b.style.background = eink ? (primary ? '#26242a' : 'transparent') : (primary ? '#ff3d8b' : 'transparent');
        b.style.borderColor = eink ? 'rgba(28,26,30,0.22)' : (primary ? '#ff3d8b' : 'rgba(255,255,255,0.08)');
      });
      p.querySelectorAll('div').forEach((d) => {
        if (d.style.letterSpacing === '0.24em') d.style.color = eink ? 'rgba(28,26,30,0.42)' : 'rgba(255,255,255,0.32)';
        if (d.style.lineHeight === '1.6') d.style.color = eink ? 'rgba(28,26,30,0.38)' : 'rgba(255,255,255,0.28)';
      });
    }
    if (this.stateRef.current) this.stateRef.current.style.color = eink ? 'rgba(28,26,30,0.7)' : '#ffa8cd';
    if (this.ampRef.current) this.ampRef.current.style.background = eink ? '#26242a' : 'linear-gradient(90deg, #ff3d8b, #7de3ff)';
    const stageBg = eink
      ? 'radial-gradient(ellipse 82% 72% at 50% 40%, #f3f0e8 0%, #e7e3d9 62%, #dbd7cc 100%)'
      : mode === 'Hologram'
        ? 'radial-gradient(ellipse 55% 48% at 50% 46%, #06222c 0%, #03101a 52%, #01060c 100%)'
        : 'radial-gradient(ellipse 70% 60% at 50% 42%, #120618 0%, #05020a 55%, #000 100%)';
    if (this.stageRef.current) this.stageRef.current.style.background = stageBg;
    document.body.style.background = eink ? '#e7e3d9' : mode === 'Hologram' ? '#01060c' : '#000';
    this.markState();
  }

  togglePanel(force) {
    this.panelHidden = force === undefined ? !this.panelHidden : !!force;
    const p = this.panelRef.current;
    if (p) {
      p.style.transition = 'opacity .45s ease, transform .45s ease';
      p.style.opacity = this.panelHidden ? '0' : '1';
      p.style.pointerEvents = this.panelHidden ? 'none' : 'auto';
      p.style.transform = this.panelHidden ? 'translateX(-50%) translateY(18px)' : 'translateX(-50%)';
    }
  }

  react(name) {
    const s = this.s;
    if (name === 'nod') { s.nodT = 1; s.nod = 0; }
    else if (name === 'surprise') { s.eyeWide = 1; s.flash = 1; s.tear = 0.45; s.tiltT = 0; }
    else if (name === 'amused') { s.squint = 1; s.tiltT = 0.055; s.flash = 0.45; }
    else if (name === 'confused') { s.tiltT = -0.10; s.wobble = 1; }
    else if (name === 'error') { s.tear = 1; s.flash = 0.3; }
    else if (name === 'wake') { s.boot = 1; s.eyeOpenT = 1; s.state = s.state === 'asleep' ? 'idle' : s.state; this.markState(); }
    else if (name === 'sleep') { this.setAvatarState('asleep'); }
    else if (name === 'thinking') { this.setAvatarState('thinking'); }
  }

  speakDemo() {
    this.setAvatarState('speaking');
    const seq = [];
    let t = 0;
    while (t < 4.6) {
      const d = 0.07 + Math.random() * 0.13;
      seq.push([t, t + d, 0.35 + Math.random() * 0.65]);
      t += d + (Math.random() < 0.18 ? 0.16 + Math.random() * 0.2 : 0.02 + Math.random() * 0.05);
    }
    this.speech = { start: performance.now() / 1000, seq, end: t + 0.3 };
  }

  ensureCtx() {
    if (!this.actx) this.actx = new (window.AudioContext || window.webkitAudioContext)();
    if (this.actx.state === 'suspended') this.actx.resume();
    if (!this.analyser) {
      this.analyser = this.actx.createAnalyser();
      this.analyser.fftSize = 1024;
      this.analyser.smoothingTimeConstant = 0.55;
      this.freq = new Uint8Array(this.analyser.frequencyBinCount);
    }
    return this.actx;
  }

  attachAudio(el) {
    const ac = this.ensureCtx();
    const src = ac.createMediaElementSource(el);
    src.connect(this.analyser);
    this.analyser.connect(ac.destination);
    this.live = true;
    this.setAvatarState('speaking');
  }

  mic() {
    if (this.micOn) {
      this.micOn = false; this.live = false;
      if (this.micStream) this.micStream.getTracks().forEach((t) => t.stop());
      if (this.micRef.current) { this.micRef.current.style.color = 'rgba(255,255,255,0.55)'; this.micRef.current.style.borderColor = 'rgba(255,255,255,0.12)'; }
      this.setAvatarState('idle');
      return;
    }
    navigator.mediaDevices.getUserMedia({ audio: true }).then((st) => {
      const ac = this.ensureCtx();
      ac.createMediaStreamSource(st).connect(this.analyser);
      this.micStream = st; this.micOn = true; this.live = true;
      if (this.micRef.current) { this.micRef.current.style.color = '#7de3ff'; this.micRef.current.style.borderColor = '#7de3ff'; }
      this.setAvatarState('listening');
    }).catch(() => {});
  }

  frame(t, now) {
    const s = this.s, ctx = this.ctx, cv = this.canvasRef.current;
    if (!ctx || !cv) return;
    const P = this.props;
    const alive = P.aliveness == null ? 0.8 : P.aliveness;
    const spacingBase = P.lineSpacing || 3.1;
    const bloomAmt = P.bloom == null ? 1 : P.bloom;
    const palName = P.palette || 'Neon Bloom';
    const mode = P.renderMode || 'Hologram';
    const eink = mode === 'E-Ink';
    if (this._mode !== mode) { this._mode = mode; this.applyChrome(mode); this._eforce = 2; }

    // E-paper refreshes in discrete jumps, not continuously. Quantising the whole
    // clock gives the real cadence (and costs a fraction of the battery).
    if (eink) {
      const hz = P.refreshHz || 7;
      const tq = Math.floor(t * hz) / hz;
      if (this._etq === tq && !this._eforce && !s.eflash) return;
      if (this._eforce) this._eforce--;
      this._etq = tq;
      t = tq;
    }

    // ---- audio / amplitude ----
    if (this.live && this.analyser) {
      this.analyser.getByteFrequencyData(this.freq);
      let lo = 0, hi = 0;
      for (let i = 2; i < 22; i++) lo += this.freq[i];
      for (let i = 22; i < 120; i++) hi += this.freq[i];
      lo /= 20 * 255; hi /= 98 * 255;
      this.s.amp = Math.min(1, lo * 1.6 + hi * 1.1);
      this.hiBand = hi;
    } else if (this.speech) {
      const st = performance.now() / 1000 - this.speech.start;
      if (st > this.speech.end) { this.speech = null; this.s.amp = 0; this.setAvatarState('idle'); }
      else {
        let a = 0;
        for (const [b, e, v] of this.speech.seq) {
          if (st >= b && st <= e) { const k = (st - b) / (e - b); a = v * Math.sin(Math.PI * k) ** 0.7; }
        }
        this.s.amp = a;
      }
    } else if (now - (this.lastAmpAt || 0) > 150) {
      // host stopped feeding amplitude: let the jaw close instead of freezing open
      s.amp *= 0.86;
      if (s.amp < 0.004) s.amp = 0;
    }
    if (s.state === 'asleep') { s.amp = 0; if (s.ampS < 0.01) s.ampS = 0; }
    s.ampS += (s.amp - s.ampS) * (s.amp > s.ampS ? 0.42 : 0.16);
    if (this.ampRef.current) this.ampRef.current.style.width = (s.ampS * 100).toFixed(1) + '%';

    // ---- state easing ----
    const target = STATE_MIX[s.state];
    for (const k in target) s.mix[k] += (target[k] - s.mix[k]) * 0.055;
    const M = s.mix;

    // ---- gaze, blinks, breath ----
    if (t - s.lastSacc > (s.state === 'listening' ? 1.4 : 0.9) + Math.random() * 2.6) {
      s.lastSacc = t;
      const r = s.state === 'listening' ? 0.35 : 1;
      s.gazeTX = (Math.random() - 0.5) * 0.9 * r;
      s.gazeTY = (Math.random() - 0.5) * 0.55 * r;
    }
    s.gazeX += (s.gazeTX - s.gazeX) * 0.12;
    s.gazeY += (s.gazeTY - s.gazeY) * 0.12;
    if (now > s.blinkAt && s.state !== 'asleep') {
      s.blinking = now; s.blinkAt = now + 2400 + Math.random() * 3600;
    }
    let blink = 1;
    if (s.blinking) {
      const k = (now - s.blinking) / 130;
      if (k >= 1) s.blinking = 0; else blink = Math.abs(Math.cos(Math.PI * k));
    }
    s.eyeOpen += (s.eyeOpenT - s.eyeOpen) * 0.1;
    s.eyeWide *= 0.955; s.squint *= 0.972; s.flash *= 0.9; s.tear *= 0.92; s.wobble *= 0.985;
    if (s.nodT > 0) { s.nod += 0.11; if (s.nod > 1) { s.nod = 0; s.nodT = 0; } }
    s.tilt += (s.tiltT - s.tilt) * 0.06;
    if (Math.abs(s.tiltT) > 0.001 && Math.random() < 0.006) s.tiltT *= 0.4;
    if (s.boot > 0) s.boot = Math.max(0, s.boot - 0.012);
    if (s.sweep >= 0) { s.sweep += 0.011; if (s.sweep > 1.25) s.sweep = s.state === 'thinking' ? 0 : -1; }

    const breath = Math.sin(t * (s.state === 'asleep' ? 0.55 : 1.15)) * alive;
    const drift = t * (s.state === 'thinking' ? 9 : 2.2);

    // ---- palette blend ----
    const base = palName === 'Cold Signal' ? 'cold' : palName === 'Ember' ? 'ember' : 'neon';
    let wn = M.neon, wc = M.cold, we = M.ember;
    if (base === 'cold') { wc += wn * 0.75; wn *= 0.25; }
    if (base === 'ember') { we += wn * 0.8 + wc * 0.4; wn *= 0.2; wc *= 0.6; }
    we += s.tear * 0.5;
    const sum = wn + wc + we || 1;
    wn /= sum; wc /= sum; we /= sum;
    const L = this.luts, W = this.work;
    for (let i = 0; i < 768; i++) W[i] = L.neon[i] * wn + L.cold[i] * wc + L.ember[i] * we;

    // ---- raster ----
    if (this.ready) {
      if (eink) this.rasterEink(t, alive);
      else if (mode === 'Hologram') this.rasterHolo(t, M, drift, alive);
      else this.raster(t, M, drift, breath, spacingBase, alive);
    }

    // ---- composite ----
    const w = cv.width, h = cv.height;
    this.bctx.putImageData(this.img, 0, 0);

    // everything composites at buffer resolution, then one upscale to screen
    const cc = this.cctx;
    cc.setTransform(1, 0, 0, 1, 0, 0);
    cc.globalCompositeOperation = 'source-over';
    cc.globalAlpha = 1;
    cc.clearRect(0, 0, BW, BH);
    cc.drawImage(this.buf, 0, 0);

    if (!eink) {
    this.g1ctx.clearRect(0, 0, this.g1.width, this.g1.height);
    this.g1ctx.filter = 'blur(2px)';
    this.g1ctx.drawImage(this.buf, 0, 0, this.g1.width, this.g1.height);
    this.g1ctx.filter = 'none';
    this.g2ctx.clearRect(0, 0, this.g2.width, this.g2.height);
    this.g2ctx.drawImage(this.g1, 0, 0, this.g2.width, this.g2.height);
    }

    if (eink) {
      this.drawEyesEink(cc, BW, BH, blink, M);
    } else {
      cc.globalCompositeOperation = 'lighter';
      cc.globalAlpha = 0.5 * bloomAmt * M.bloom;
      cc.drawImage(this.g1, 0, 0, BW, BH);
      cc.globalAlpha = (0.42 + s.flash * 0.45) * bloomAmt * M.bloom;
      cc.drawImage(this.g2, -BW * 0.06, -BH * 0.05, BW * 1.12, BH * 1.1);
      cc.globalAlpha = 1;
      this.drawEyes(cc, 0, 0, BW, BH, blink, M, t, mode !== 'Hologram');
    }

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    if (eink) { ctx.fillStyle = 'rgb(231,227,217)'; ctx.fillRect(0, 0, w, h); }

    // e-paper cannot render smooth motion, so the plate holds still and the
    // life comes from discrete refreshes instead of drift
    const fit = eink
      ? (h / BH) * 0.98
      : Math.min(w / BW, h / BH) * 0.70;
    const scale = eink ? fit : fit * (1 + breath * 0.004);
    const dw = BW * scale, dh = BH * scale;
    const cxp = eink ? w / 2 : w / 2 + Math.sin(t * 0.31) * 6 * this.dpr * alive;
    const cyp = eink
      ? h / 2 - Math.sin(s.nod * Math.PI) * 6 * this.dpr
      : h * 0.435 + Math.sin(t * 0.47) * 5 * this.dpr * alive - Math.sin(s.nod * Math.PI) * 22 * this.dpr;

    ctx.save();
    ctx.translate(cxp, cyp);
    if (!eink) ctx.rotate(s.tilt + Math.sin(t * 0.6) * 0.004 * alive + Math.sin(t * 7) * 0.006 * s.wobble);
    ctx.imageSmoothingEnabled = !eink;
    ctx.drawImage(this.comp, -dw / 2, -dh / 2, dw, dh);
    if (eink) {
      ctx.strokeStyle = 'rgba(28,26,30,0.5)';
      ctx.lineWidth = Math.max(1, this.dpr);
      ctx.strokeRect(-dw / 2, -dh / 2, dw, dh);
    }
    ctx.restore();

    // full-refresh flash: e-paper inverts the plate before repainting it
    if (eink && s.eflash > 0) {
      ctx.globalCompositeOperation = s.eflash > 0.5 ? 'difference' : 'source-over';
      ctx.fillStyle = s.eflash > 0.5 ? '#ffffff' : 'rgba(231,227,217,' + (s.eflash * 1.6) + ')';
      ctx.fillRect(0, 0, w, h);
      ctx.globalCompositeOperation = 'source-over';
      s.eflash -= 0.34;
      if (s.eflash < 0) s.eflash = 0;
    }

    // thinking sweep
    if (s.sweep >= 0 && !eink) {
      const y = (s.sweep * 1.1 - 0.05) * h;
      const g = ctx.createLinearGradient(0, y - 90 * this.dpr, 0, y + 30 * this.dpr);
      g.addColorStop(0, 'rgba(125,227,255,0)');
      g.addColorStop(0.8, 'rgba(125,227,255,0.14)');
      g.addColorStop(1, 'rgba(125,227,255,0)');
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = g;
      ctx.fillRect(0, y - 90 * this.dpr, w, 120 * this.dpr);
    }
    // e-ink thinking cue: a partial-refresh bar wiping down the plate
    if (s.sweep >= 0 && eink) {
      const y = (s.sweep * 1.1 - 0.05) * h;
      ctx.globalCompositeOperation = 'difference';
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, y, w, 3 * this.dpr);
      ctx.globalCompositeOperation = 'source-over';
    }
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;

    if (this.dotRef.current) {
      const c = eink
        ? (s.state === 'asleep' ? 'rgba(28,26,30,0.25)' : '#26242a')
        : s.state === 'listening' ? '#7de3ff' : s.state === 'asleep' ? '#4a4358' : s.state === 'thinking' ? '#b06cff' : '#ff3d8b';
      if (this.dotRef.current.style.background !== c) this.dotRef.current.style.background = c;
    }
  }

  raster(t, M, drift, breath, spacingBase, alive) {
    const lum = this.lum, out = this.img.data, W = this.work, s = this.s, noise = this.noise;
    const spacing = Math.max(1.6, spacingBase * M.spacing);
    const intensity = M.intensity * (1 + s.flash * 0.5) * (s.boot > 0 ? 1 - s.boot * 0.85 : 1);
    const jaw = Math.pow(s.ampS, 0.75);
    const glitch = M.glitch;
    const tear = s.tear;
    const bootLine = s.boot > 0 ? (1 - s.boot) * BH * 1.3 : BH * 2;

    for (let y = 0; y < BH; y++) {
      const ny = y / BH;
      // scanline gate
      const ph = (y + drift) % spacing;
      let gate = ph < 1 ? 1 : ph < 1.9 ? 1 - (ph - 1) / 0.9 : 0.055;
      gate = 0.06 + gate * 0.94;

      // jaw band: rows below the mouth line stretch downward with amplitude
      const jt = ny > FACE_JAW ? Math.min(1, (ny - FACE_JAW) / 0.16) : 0;
      const jawShift = jaw * jt * 13 + Math.sin(t * 22 + y * 0.4) * jaw * jt * 1.6;

      // horizontal displacement: breathing wave + glitch shear + speech ripple
      let sh = Math.sin(ny * 9 + t * 0.9) * 1.4 * alive;
      const gseed = noise[(y * 7 + (t * 3 | 0) * 13) % noise.length];
      if (gseed < glitch * 0.16) sh += (gseed / (glitch * 0.16) - 0.5) * 26;
      if (s.state === 'listening') sh += Math.sin(ny * 26 - t * 5.5) * (1.2 + s.ampS * 5);
      if (jt > 0) sh += Math.sin(t * 16 + ny * 30) * jaw * jt * 2.4;

      const fade = y > bootLine ? 0 : 1;
      const rowI = y * BW;
      const srcYf = y - jawShift;
      const sy = srcYf < 0 ? 0 : srcYf > BH - 1 ? BH - 1 : srcYf | 0;
      const syI = sy * BW;
      const syT = ((sy + (tear > 0.02 ? -2 : 0)) < 0 ? 0 : sy + (tear > 0.02 ? -2 : 0)) * BW;

      for (let x = 0; x < BW; x++) {
        const p = (rowI + x) * 4;
        out[p + 3] = 255;
        if (!fade) { out[p] = 0; out[p + 1] = 0; out[p + 2] = 0; continue; }
        const sxf = x - sh;
        const sx = sxf < 0 ? 0 : sxf > BW - 1 ? BW - 1 : sxf | 0;
        let v = lum[syI + sx];
        if (v > 0.02) {
          const n = noise[rowI + x];
          const dot = 0.62 + 0.38 * (((x + (drift | 0)) % 3) === 0 ? 1 : 0.55);
          v = v * gate * dot * intensity * (n > 0.955 ? 0.25 : 1);
        } else { v = 0; }
        let q = v * 255;
        q = q < 0 ? 0 : q > 255 ? 255 : q | 0;
        const li = q * 3;
        if (tear > 0.02) {
          const sx2 = x + tear * 7 | 0;
          const v2 = lum[syT + (sx2 > BW - 1 ? BW - 1 : sx2)] * gate * intensity;
          let q2 = v2 * 255; q2 = q2 < 0 ? 0 : q2 > 255 ? 255 : q2 | 0;
          out[p] = W[q2 * 3] * tear + W[li] * (1 - tear * 0.4);
          out[p + 1] = W[li + 1] * (1 - tear * 0.5);
          out[p + 2] = W[li + 2] * (1 - tear * 0.2) + W[q2 * 3 + 2] * tear * 0.5;
        } else {
          out[p] = W[li];
          out[p + 1] = W[li + 1];
          out[p + 2] = W[li + 2];
        }
      }
    }
  }

  rasterHolo(t, M, drift, alive) {
    const rgb = this.rgb, raw = this.raw, edge = this.edge, out = this.img.data, s = this.s, noise = this.noise;
    const jaw = Math.pow(s.ampS, 0.75);
    const intensity = M.intensity * (1 + s.flash * 0.45) * (s.boot > 0 ? 1 - s.boot * 0.8 : 1);
    const tear = s.tear;
    // projector flicker: two beat frequencies plus a little noise
    const flick = 0.88 + 0.09 * Math.sin(t * 31) * Math.sin(t * 11.7)
      + (noise[(t * 24 | 0) % noise.length] - 0.5) * 0.05;
    // a signal dropout band travelling up the volume
    const dropY = ((t * 0.28) % 1.5) - 0.25;
    const bootLine = s.boot > 0 ? (1 - s.boot) * BH * 1.25 : BH * 2;
    const split = 1.1 + s.ampS * 1.6 + tear * 5;

    for (let y = 0; y < BH; y++) {
      const ny = y / BH;
      // interlace: the projection is rebuilt line by line
      const ph = (y + drift * 1.6) % 3;
      const scan = ph < 1 ? 1 : ph < 2 ? 0.66 : 0.42;
      const drop = Math.abs(ny - dropY) < 0.022 ? 0.3 : 1;

      const jt = ny > FACE_JAW ? Math.min(1, (ny - FACE_JAW) / 0.15) : 0;
      const jawShift = jaw * jt * 11 + Math.sin(t * 20 + y * 0.35) * jaw * jt * 1.4;

      let sh = Math.sin(ny * 11 + t * 1.25) * 1.3 * alive;
      const gseed = noise[(y * 7 + (t * 3 | 0) * 13) % noise.length];
      if (gseed < M.glitch * 0.1) sh += (gseed / (M.glitch * 0.1) - 0.5) * 20;
      if (s.state === 'listening') sh += Math.sin(ny * 24 - t * 5) * (0.9 + s.ampS * 4);
      if (jt > 0) sh += Math.sin(t * 15 + ny * 28) * jaw * jt * 2;

      const rowI = y * BW;
      const live = y > bootLine ? 0 : 1;
      const srcYf = y - jawShift;
      const sy = srcYf < 0 ? 0 : srcYf > BH - 1 ? BH - 1 : srcYf | 0;
      const syI = sy * BW;
      const rowGain = scan * drop * flick * intensity;

      for (let x = 0; x < BW; x++) {
        const p = (rowI + x) * 4;
        if (!live) { out[p + 3] = 0; continue; }
        const sxf = x - sh;
        const sx = sxf < 0 ? 0 : sxf > BW - 1 ? BW - 1 : sxf | 0;
        // chromatic split: red and blue are sampled either side of green
        const xr = sx + split < BW ? (sx + split) | 0 : BW - 1;
        const xb = sx - split > 0 ? (sx - split) | 0 : 0;
        // contours emit, flat fill only glows faintly — a volume, not a poster
        const e = edge[syI + sx];
        const eR = edge[syI + xr], eB = edge[syI + xb];
        const body = raw[syI + sx];
        const vg = e * 1.05 + body * 0.20;
        const vr = eR * 1.05 + raw[syI + xr] * 0.20;
        const vb = eB * 1.05 + raw[syI + xb] * 0.20;
        let a = vg > vr ? vg : vr; if (vb > a) a = vb;
        if (a <= 0.02) { out[p + 3] = 0; continue; }
        if (a > 1) a = 1;
        const ci = (syI + sx) * 3;
        out[p] = vr * rowGain * 120 + rgb[ci] * 0.1;
        out[p + 1] = vg * rowGain * 235 + rgb[ci + 1] * 0.07;
        out[p + 2] = vb * rowGain * 255 + rgb[ci + 2] * 0.09;
        out[p + 3] = (0.25 + a * 0.75) * a * 255 * rowGain;
      }
    }
  }

  rasterEink(t, alive) {
    // e-ink works from the untouched photographic tone, not the neon curve
    const lum = this.raw, out = this.img.data, s = this.s, noise = this.noise;
    if (!this.prevInk) this.prevInk = new Uint8Array(BW * BH);
    const prev = this.prevInk;
    const jaw = Math.pow(s.ampS, 0.75);
    // asleep dims the plate toward paper; surprise/amused push ink darker
    const gain = (s.state === 'asleep' ? 0.62 : 1) * (1 + s.flash * 0.25);
    const bias = s.state === 'asleep' ? 0.2 : 0;
    const tear = s.tear;

    for (let y = 0; y < BH; y++) {
      const ny = y / BH;
      // jaw band: the plate below the mouth stretches with amplitude
      const jt = ny > FACE_JAW ? Math.min(1, (ny - FACE_JAW) / 0.16) : 0;
      const jawShift = jaw * jt * 12;
      let sh = Math.sin(ny * 7 + t * 0.7) * 1.1 * alive;
      if (jt > 0) sh += Math.sin(t * 9 + ny * 24) * jaw * jt * 1.8;
      if (tear > 0.02) sh += (noise[(y * 13) % noise.length] - 0.5) * tear * 9;

      const rowI = y * BW;
      const srcYf = y - jawShift;
      const sy = srcYf < 0 ? 0 : srcYf > BH - 1 ? BH - 1 : srcYf | 0;
      const syI = sy * BW;
      const bRow = (y & 7) * 8;

      for (let x = 0; x < BW; x++) {
        const i = rowI + x;
        const p = i * 4;
        const sxf = x - sh;
        const sx = sxf < 0 ? 0 : sxf > BW - 1 ? BW - 1 : sxf | 0;
        const si = syI + sx;
        let dark = (1 - lum[si] - 0.06) * 1.32;
        dark = dark * gain - bias;
        const ink = dark > BAYER[bRow + (x & 7)] ? 1 : 0;
        out[p + 3] = 255;
        if (ink) {
          out[p] = INK[0]; out[p + 1] = INK[1]; out[p + 2] = INK[2];
        } else if (prev[i] && noise[i] < 0.4) {
          // partial-refresh ghosting: ink that just cleared leaves a faint trace
          out[p] = GHOST[0]; out[p + 1] = GHOST[1]; out[p + 2] = GHOST[2];
        } else {
          out[p] = PAPER[0]; out[p + 1] = PAPER[1]; out[p + 2] = PAPER[2];
        }
        prev[i] = ink;
      }
    }
  }

  drawEyesEink(ctx, dw, dh, blink, M) {
    const s = this.s;
    const open = Math.max(0.02, blink * s.eyeOpen * M.open * (1 + s.eyeWide * 0.45) * (1 - s.squint * 0.7));
    ctx.globalCompositeOperation = 'source-over';
    for (const e of [EYE_L, EYE_R]) {
      const ex = e[0] * dw + s.gazeX * dw * 0.011;
      const ey = e[1] * dh + s.gazeY * dh * 0.007;
      const rw = dw * 0.030, rh = dh * 0.017 * open;
      // iris as solid ink, so gaze and blink still read on a 1-bit plate
      ctx.fillStyle = 'rgb(' + INK.join(',') + ')';
      ctx.beginPath();
      ctx.ellipse(ex, ey, rw, Math.max(0.7, rh), 0, 0, Math.PI * 2);
      ctx.fill();
      if (open > 0.35) {
        ctx.fillStyle = 'rgb(' + PAPER.join(',') + ')';
        ctx.beginPath();
        ctx.ellipse(ex - rw * 0.32, ey - rh * 0.3, rw * 0.2, Math.max(0.5, rh * 0.24), 0, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  drawEyes(ctx, dx, dy, dw, dh, blink, M, t, drawIris) {
    const s = this.s;
    const open = Math.max(0.02, blink * s.eyeOpen * M.open * (1 + s.eyeWide * 0.5) * (1 - s.squint * 0.72));
    const accent = s.state === 'listening' ? [125, 227, 255] : s.state === 'thinking' ? [176, 108, 255] : [255, 120, 175];
    ctx.globalCompositeOperation = 'lighter';
    for (const e of (drawIris === false ? [] : [EYE_L, EYE_R])) {
      const ex = dx + e[0] * dw + s.gazeX * dw * 0.012;
      const ey = dy + e[1] * dh + s.gazeY * dh * 0.008;
      const rw = dw * 0.038 * EYE_SCALE, rh = dh * 0.019 * EYE_SCALE * open;
      ctx.save();
      ctx.beginPath();
      ctx.ellipse(ex, ey, rw, Math.max(0.6, rh), 0, 0, Math.PI * 2);
      ctx.clip();
      const g = ctx.createRadialGradient(ex, ey, 0, ex, ey, rw * 1.9);
      g.addColorStop(0, 'rgba(255,255,255,' + (0.8 * (0.4 + open * 0.6)) + ')');
      g.addColorStop(0.2, 'rgba(' + accent.join(',') + ',0.7)');
      g.addColorStop(0.55, 'rgba(' + accent.join(',') + ',0.18)');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g;
      ctx.fillRect(ex - rw * 2, ey - rw * 2, rw * 4, rw * 4);
      ctx.restore();
      // outer halo
      const g2 = ctx.createRadialGradient(ex, ey, 0, ex, ey, rw * 3.4);
      g2.addColorStop(0, 'rgba(' + accent.join(',') + ',' + (0.13 * open) + ')');
      g2.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g2;
      ctx.fillRect(ex - rw * 3.6, ey - rw * 3.6, rw * 7.2, rw * 7.2);
    }
    // mouth core glow, driven by amplitude
    if (s.ampS > 0.01) {
      const mx = dx + MOUTH[0] * dw, my = dy + MOUTH[1] * dh + s.ampS * dh * 0.012;
      const r = dw * (0.05 + s.ampS * 0.075) * MOUTH_SCALE;
      const g = ctx.createRadialGradient(mx, my, 0, mx, my, r);
      g.addColorStop(0, 'rgba(255,150,195,' + (0.5 * s.ampS) + ')');
      g.addColorStop(0.5, 'rgba(255,61,139,' + (0.22 * s.ampS) + ')');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g;
      ctx.fillRect(mx - r, my - r, r * 2, r * 2);
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  renderVals() {
    const A = (n) => () => this.react(n);
    const S = (n) => () => this.setAvatarState(n);
    return {
      canvasRef: this.canvasRef,
      stageRef: this.stageRef,
      srcRef: this.srcRef,
      panelRef: this.panelRef,
      stateRef: this.stateRef,
      ampRef: this.ampRef,
      dotRef: this.dotRef,
      micRef: this.micRef,
      act: {
        idle: S('idle'), listening: S('listening'), thinking: S('thinking'),
        speaking: S('speaking'), asleep: S('asleep'),
        nod: A('nod'), surprise: A('surprise'), amused: A('amused'),
        confused: A('confused'), error: A('error'), wake: A('wake'), sleep: A('sleep'),
        speak: () => this.speakDemo(),
        mic: () => this.mic()
      }
    };
  }
}

