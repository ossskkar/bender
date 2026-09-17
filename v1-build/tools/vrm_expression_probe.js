(async () => {
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  for (let i = 0; i < 80 && !window.devSet; i++) await wait(250);
  const em = window.__vrm.expressionManager;
  const face = em.getExpression('blink')._binds[0].primitives[0];
  const names = Object.keys(face.morphTargetDictionary);
  const zero = { aa: 0, blink: 0, blinkLeft: 0, blinkRight: 0, happy: 0, sad: 0, angry: 0, surprised: 0, relaxed: 0, attentive: 0, thinking: 0, sleepy: 0 };
  const nz = () => Object.fromEntries(names.map(n => [n, +face.morphTargetInfluences[face.morphTargetDictionary[n]].toFixed(3)]).filter(([, v]) => v));
  const out = { warnings: '' };
  for (const e of ['happy', 'sad', 'surprised', 'thinking']) {
    devSet({ ...zero, [e]: 1 }); await wait(400); out[e] = nz();
    devSet({ ...zero, [e]: 1, blink: 1, aa: 0.8 }); await wait(400); out[e + '+blink+aa'] = nz();
  }
  out.binds = Object.fromEntries(['happy','sad','surprised','thinking'].map(e => [e, (em.getExpression(e)._binds||[]).length]));
  out.warnings = document.getElementById('dev-warn').textContent;
  __log.push(JSON.stringify(out));
})(); 0
