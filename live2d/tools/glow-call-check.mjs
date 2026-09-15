#!/usr/bin/env node
// The glow survives a call, checked in a real Chrome.
//
//   node glow-call-check.mjs <face-page-url>
//
// During a call the host sends setGlow({loud}) on every audio frame. If that
// empties --state, the #glow gradients become invalid and its computed
// background-image is 'none': no light at all, which is what Oscar saw on
// 2026-09-16. This sets a full thinking state, sends a loud-only update, and
// reads the computed background back. Needs no drawn model. Exit 0 = pass.
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const url = process.argv[2];
if (!url) { console.error('usage: glow-call-check.mjs <face-page-url>'); process.exit(2); }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const port = 9800 + Math.floor(Math.random() * 100);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', `--user-data-dir=${mkdtempSync(join(tmpdir(), 'glow-check-'))}`,
  `--remote-debugging-port=${port}`, '--no-first-run', '--window-size=400,800', 'about:blank',
], { stdio: 'ignore' });

let page;
for (let i = 0; i < 100 && !page; i++) {
  try { page = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page'); }
  catch { await sleep(100); }
}
if (!page) { chrome.kill('SIGKILL'); console.error('Chrome never came up (screen locked?)'); process.exit(2); }

const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); pending.get(m.id)?.(m); });
const send = (method, params = {}) => new Promise((r) => { pending.set(++id, r); ws.send(JSON.stringify({ id, method, params })); });
const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result?.result?.value;

await send('Page.navigate', { url });
for (let i = 0; i < 60 && !(await evaluate('!!(window.ArisuScene && document.getElementById("glow"))')); i++) await sleep(250);

const bg = 'getComputedStyle(document.getElementById("glow")).backgroundImage';
const result = await evaluate(`(function () {
  var S = window.ArisuScene;
  if (!S || !S.setGlow) return { error: 'no ArisuScene.setGlow' };
  S.setGlow({ state: 'thinking', colour: '255, 176, 59', glow: 1, size: 1, x: 54, y: 42, loud: 0 });
  var before = ${bg};
  S.setGlow({ loud: 0.5 });
  var after = ${bg};
  return { before: before.slice(0, 60), after: after.slice(0, 60),
           thinkingColour: after.indexOf('255, 176, 59') >= 0,
           cls: document.getElementById('glow').className };
})()`);
ws.close(); chrome.kill('SIGKILL');

console.log(JSON.stringify(result));
const ok = result && !result.error && result.before !== 'none' && result.after !== 'none'
  && result.thinkingColour && result.cls === 'thinking';
console.log(ok ? 'PASS' : 'FAIL');
process.exit(ok ? 0 : 1);
