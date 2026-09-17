import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { VRMLoaderPlugin } from '@pixiv/three-vrm';
const post = (o) => window.webkit.messageHandlers.log.postMessage(o);
const say = (...a) => post({ type: 'log', text: a.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join(' ') });
window.onerror = (m) => say('ERROR', String(m));
const W = 640, H = 640;
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H); renderer.setPixelRatio(1); renderer.setClearColor(0x26404e);
document.body.appendChild(renderer.domElement);
const scene = new THREE.Scene();
scene.add(new THREE.AmbientLight(0xffffff, 1.2));
const sun = new THREE.DirectionalLight(0xffffff, 1.6); sun.position.set(0.3, 1.5, 2); scene.add(sun);
const camera = new THREE.PerspectiveCamera(14, 1, 0.05, 20);
const loader = new GLTFLoader(); loader.register(p => new VRMLoaderPlugin(p));
const REQ = ['aa','ih','ou','ee','oh','blink','blinkLeft','blinkRight','neutral','happy','sad','angry','surprised','relaxed','attentive','thinking','sleepy'];
loader.load('./test.vrm', async (gltf) => {
  const vrm = gltf.userData.vrm; scene.add(vrm.scene);
  vrm.scene.traverse(o => { o.frustumCulled = false; });
  if (vrm.lookAt) vrm.lookAt.target = undefined;
  vrm.update(0);
  const em = vrm.expressionManager;
  const head = vrm.humanoid.getNormalizedBoneNode('head').getWorldPosition(new THREE.Vector3());
  const lEye = vrm.humanoid.getRawBoneNode('leftEye'), rEye = vrm.humanoid.getRawBoneNode('rightEye');
  const eyeY = lEye ? lEye.getWorldPosition(new THREE.Vector3()).y : head.y + 0.06;
  camera.position.set(0, eyeY - 0.02, 1.35); camera.lookAt(0, eyeY - 0.02, 0);
  // runtime inventory
  const map = em.expressionMap;
  const inv = {};
  for (const n of REQ) { const e = map[n]; inv[n] = e ? { exists: true, isBinary: e.isBinary, overrideBlink: e.overrideBlink, overrideMouth: e.overrideMouth, overrideLookAt: e.overrideLookAt, binds: (e._binds || []).length } : { exists: false }; }
  say('INVENTORY_ALL', Object.keys(map));
  say('INVENTORY', inv);
  say('LEFT_EYE_BONE_X', lEye ? +lEye.getWorldPosition(new THREE.Vector3()).x.toFixed(4) : null, 'eyeY', +eyeY.toFixed(4));
  // face mesh primitive for morph influence + region analysis
  const prims = map.blink._binds[0].primitives; const prim = prims[0];
  const dict = prim.morphTargetDictionary, names = Object.keys(dict);
  const wpos = new THREE.Vector3();
  say('FACE_PRIMITIVES', prims.map(p => ({ name: p.name, verts: p.geometry.attributes.position.count, material: p.material?.name })));
  const PD = prims.map(p => { const pos = p.geometry.attributes.position, N = pos.count, vy = new Float32Array(N), vx = new Float32Array(N);
    for (let i = 0; i < N; i++) { wpos.fromBufferAttribute(pos, i).applyMatrix4(p.matrixWorld); vy[i] = wpos.y; vx[i] = wpos.x; }
    return { p, pos, N, vy, vx, morphs: p.geometry.morphAttributes.position, rel: p.geometry.morphTargetsRelative }; });
  const regions = () => { const r = { eyesBrows_L: 0, eyesBrows_R: 0, mouthJaw: 0, other: 0 };
    for (const { p, pos, N, vy, vx, morphs, rel } of PD) { const d = new Float32Array(N * 3); let any = false;
      p.morphTargetInfluences.forEach((w, k) => { if (!w || !morphs) return; any = true; const a = morphs[k];
        for (let i = 0; i < N; i++) { d[i*3] += w*(rel ? a.getX(i) : a.getX(i)-pos.getX(i)); d[i*3+1] += w*(rel ? a.getY(i) : a.getY(i)-pos.getY(i)); d[i*3+2] += w*(rel ? a.getZ(i) : a.getZ(i)-pos.getZ(i)); } });
      if (!any) continue;
      for (let i = 0; i < N; i++) { const m = Math.hypot(d[i*3], d[i*3+1], d[i*3+2]) * 1000; if (m < 0.05) continue;
        let k; if (vy[i] > eyeY - 0.022) k = vx[i] >= 0 ? 'eyesBrows_L' : 'eyesBrows_R'; else if (vy[i] < eyeY - 0.035) k = 'mouthJaw'; else k = 'other';
        if (m > r[k]) r[k] = m; } }
    for (const k in r) r[k] = +r[k].toFixed(2); return r; };
  const active = () => Object.fromEntries(names.map(n => [n, +prim.morphTargetInfluences[dict[n]].toFixed(3)]).filter(([, v]) => v));
  const run = (label, req) => {
    for (const n of Object.keys(map)) em.setValue(n, 0);
    for (const [n, v] of Object.entries(req)) em.setValue(n, v);
    vrm.update(0);
    renderer.render(scene, camera);
    const got = Object.fromEntries(Object.keys(req).map(n => [n, +(em.getValue(n) ?? NaN).toFixed(3)]));
    const res = { label, requested: req, getValue: got, activeMorphs: active(), maxDisplacement_mm: regions(),
      overrideMultipliers: (() => { try { return em._calculateWeightMultipliers(); } catch (e) { return 'n/a: ' + e; } })() };
    say('RESULT', res);
    post({ type: 'png', name: label, data: renderer.domElement.toDataURL('image/png') });
  };
  run('neutral_zero', {});
  for (const e of ['aa','ih','ou','ee','oh']) for (const w of [0, 0.25, 0.5, 0.75, 1]) run(`${e}_${w}`, { [e]: w });
  for (const e of ['blink','blinkLeft','blinkRight']) for (const w of [0, 0.5, 1]) run(`${e}_${w}`, { [e]: w });
  for (const e of ['neutral','happy','sad','angry','surprised','relaxed','attentive','thinking','sleepy']) run(`${e}_1`, { [e]: 1 });
  run('A_blink+aa', { blink: 1, aa: 0.8 }); run('B_blinkLeft+aa', { blinkLeft: 1, aa: 0.8 }); run('C_blinkRight+aa', { blinkRight: 1, aa: 0.8 });
  for (const e of ['happy','sad','angry','surprised','relaxed','attentive','thinking']) {
    run(`D_${e}+aa`, { [e]: 1, aa: 0.8 }); run(`E_${e}+blink`, { [e]: 1, blink: 1 }); run(`F_${e}+blink+aa`, { [e]: 1, blink: 1, aa: 0.8 }); }
  run('G_sleepy+aa', { sleepy: 1, aa: 0.8 }); run('H_sleepy+blink', { sleepy: 1, blink: 1 }); run('I_sleepy+blink+aa', { sleepy: 1, blink: 1, aa: 0.8 });
  // lookAt blocking: none of the loaded expressions should block lookAt
  say('LOOKAT_TYPE', vrm.lookAt ? vrm.lookAt.applier?.constructor?.name : null);
  post({ type: 'done' });
}, undefined, (e) => { say('LOAD_FAIL', String(e)); post({ type: 'done' }); });
