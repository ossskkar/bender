// setGlow is a patch: a {loud}-only call (every audio frame of a call) must not blank the colour.
const fs = require('fs'), vm = require('vm');
const props = {}, el = { className: '' };
const style = { setProperty: (k, v) => { props[k] = v; } };
const document = { documentElement: { style }, getElementById: id => id === 'glow' ? el : null,
  addEventListener() {}, createElement: () => ({ style: {}, getContext: () => null }), body: null, readyState: 'loading' };
const window = { location: { search: '' }, addEventListener() {}, document };
const ctx = vm.createContext({ window, document, location: window.location, URLSearchParams, console, setTimeout, Image: function () {} });
vm.runInContext(fs.readFileSync(__dirname + '/../glue/arisu-scene.js', 'utf8'), ctx);
const S = window.ArisuScene;
S.setGlow({ state: 'thinking', colour: '255, 176, 59', glow: 1, size: 1, x: 54, y: 42, loud: 0 });
S.setGlow({ loud: 0.5 });
console.log(props, el.className);
if (props['--state'] !== '255, 176, 59' || props['--glow'] !== '1' || props['--loud'] !== '0.5' || el.className !== 'thinking') { console.log('FAIL'); process.exit(1); }
console.log('PASS');
