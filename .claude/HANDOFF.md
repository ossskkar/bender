# HANDOFF — Arisu (2026-09-12)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

## State

**Everything below is committed and pushed.** arisu on `origin` only — there is
no `architect` remote here.

**Her next face is decided: Live2D, and the prototype clears its gate.** The
whole avatar question was reopened this session and closed. 3D is out. Booth's
VRM catalogue and Meshy are both rejected — Meshy auto-rigs a body and leaves
the facial blendshapes as a manual Blender step, which is the only part that
matters for something that is mostly a face and a voice.

**Step 3 passed on real hardware.** The Cubism sample demo renders and animates
smoothly in Safari on the Mac *and* on the iPad over tailnet, with all eight
models cycling on tap. That was the gate on the whole direction, and it held.

**The rig is standing.** `CubismSdkForWeb-5-r.5` unpacked to
`live2d/CubismSdkForWeb`, gitignored. Built output served by the `live2d` entry
in `claude-projects/.claude/launch.json` on port 5001, fronted for the iPad by
`tailscale serve` on `https://oscars-macbook-pro.tailaa64e9.ts.net:8444/`.

**Nothing of Arisu's own is wired to it yet.** The existing portrait renderer
(`faces/renderer.js`) is untouched and still what ships. This is a parallel
prototype, not a replacement.

**The full plan, model audit and every licence finding live in `LIVE2D.md`.**
Read that, not this, for detail.

## Decisions & open questions

- **Settled: Live2D via Cubism SDK for Web, inside a `WKWebView`** so iPad and
  web stay one codebase. The seam to the voice loop is deliberately narrow:
  audio to amplitude to `ParamMouthOpenY`.
- **Settled: prototype on Natori**, not Hiyori. Hiyori is the obvious default
  and ships **zero expressions**; Mao has **no `ParamMouthOpenY` at all**.
  Natori is the only sample clearing the whole checklist. Haru is the fallback
  and is what the demo loads first.
- **Checked, and it opens the market back up: the "no AI" clause on BOOTH
  listings means no AI *learning*.** It is not a ban on an AI character. The
  listings carrying it permit app and VTuber use outright.
- **Open, and his: which character to actually buy.** Not urgent — step 6, and
  deliberately last.
- Everything from the previous handoff stays open: Chopper's portrait and
  voice, the browser client joining the room, the deferred six-character iPad
  split.

## Next steps

1. **Step 4 — wire Arisu's audio to `ParamMouthOpenY`.** The browser client
   already taps her *output* stream for the existing face; reuse that analyser
   rather than the microphone. This is the same lesson as the app's lip sync.
2. Step 5 — auto-blink and idle motion.
3. Step 6 — only then choose and buy the real character, checking each listing
   for app use, modification and AI learning.

## Gotchas

- **Do not use the Vite dev server for anything on the iPad.** Its HMR socket
  cannot reach back through the tailscale proxy, gives up, and reloads the page
  every few seconds. It looks like a stuttering avatar and it also interrupts
  model loading, which looks like models failing to load. Build and serve
  `dist` instead.
- **The `CubismWebSamples` GitHub repo is a trap.** It ships neither Core nor
  its Framework submodule and cannot build. The licence-gated SDK zip is
  self-contained; use only that.
- **Background but no model, clean console, every asset 200, is not a bug.** A
  tab that is not frontmost pauses the render loop and looks exactly like that.
- **`vite.config.mts` carries local edits inside the gitignored SDK tree** —
  `allowedHosts` and the preview block. Re-unpacking the zip silently loses
  them, and the iPad then gets a bare 403 on every file. `LIVE2D.md` has them.
- Unchanged: arisu has only `origin`; `arisu/deploy.sh` is the dead Mac path;
  her voice and her memory fail separately.

## Resume

Brief as: the avatar question is settled and proven. Live2D on the Cubism Web
SDK renders smoothly on the iPad, which was the gate, and the eight sample
models have been audited — use Natori, not Hiyori. Nothing of Arisu's own is
wired to it yet. The next build is step 4, lip sync, and the fix is already
known from the browser client: tap her output stream, not the microphone.
