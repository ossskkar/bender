# HANDOFF — Arisu (2026-09-12)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

## State

**Everything below is committed and pushed.** arisu on `origin` only — there is
no `architect` remote here.

**Step 4 is done: her audio drives `ParamMouthOpenY`.** Verified end to end on
Natori — real audio through the analyser, through the expander, into the model,
mouth visibly opening and closing in the rendered frame. Steps 1–3 were already
done; the avatar direction itself was settled last session and still holds.

**Everything we add to the SDK tree now lives in `live2d/glue/` and is applied
by `live2d/patch-sdk.sh`.** The SDK is gitignored, so edits made inside it die
when the zip is re-unpacked — that already cost a session once. The script is
idempotent and applies all five edits: vite config, the two scripts, the
`index.html` tags, the `lappmodel.ts` hook, and Natori first in the model list.

**Nothing of Arisu's own voice loop is connected yet.** The prototype is driven
by a test overlay with three buttons — demo, wav, mic. `attachStream()` is the
real seam and is written but unused. The portrait renderer (`faces/renderer.js`)
is untouched and still what ships.

**The full account of step 4, including the measurements, is in `LIVE2D.md`.**
Read that, not this.

## Decisions & open questions

- **Settled: the mouth is driven by an expander, not a gain.** The portrait's
  band math was reused verbatim and is proven; reusing its *gain* was wrong.
  Raw band energy on real speech runs 0.87 quiet against a 1.74 peak, both above
  where `ParamMouthOpenY` clamps, so a fixed gain leaves the mouth hanging open.
  Half the running peak is treated as closed. A tracked running minimum was
  tried first and converges far too slowly to use inside one utterance.
- **Open, and worth an eye: this was tuned against a sample wav, not her TTS.**
  The expander is level-independent by design, so it should carry, but
  `FLOOR_RATIO` in `live2d/glue/arisu-lipsync.js` is the knob — raise it if her
  mouth looks lazy, lower it if it twitches.
- **Open, and his: which character to actually buy.** Step 6, deliberately last.
- Everything from the previous handoff stays open: Chopper's portrait and voice,
  the browser client joining the room, the deferred six-character iPad split.

## Next steps

1. **Step 5 — auto-blink and idle motion.** Natori declares an `EyeBlink` group
   (`ParamEyeLOpen`/`ParamEyeROpen`) and ships 11 expressions and 8 motions, so
   most of this is wiring the SDK's own updaters rather than new code.
2. **Step 4b — connect `attachStream()` to her real output track** in the
   browser client, replacing the test overlay. The seam exists; nothing calls it.
3. Step 6 — only then choose and buy the real character, checking each listing
   for app use, modification and AI learning.

## Gotchas

- **`requestAnimationFrame` stops dead when the page is not visible**, and a
  hidden browser pane counts. The symptom is `__arisuMouth` staying `undefined`
  with a clean console and every asset at 200. Check visibility *first*.
  `ArisuLipSync.value()` can be pumped by hand to test the audio path without
  the render loop.
- **`value()` advances its own smoothing.** Exactly once per frame, or the jaw
  moves at double speed. The test overlay's meter reads `__arisuMouth` instead.
- **Re-unpacking the SDK zip silently reverts every edit.** Run
  `live2d/patch-sdk.sh`. If it reports an anchor it cannot find, the SDK version
  changed and the patch needs re-deriving by hand.
- **Do not use the Vite dev server for anything on the iPad.** Its HMR socket
  cannot reach back through the tailscale proxy, gives up, and reloads the page
  every few seconds. It reads as a stuttering avatar. Build and serve `dist`.
- **The `CubismWebSamples` GitHub repo is a trap.** Neither Core nor its
  Framework submodule. Only the licence-gated SDK zip builds.
- Unchanged: arisu has only `origin`; `arisu/deploy.sh` is the dead Mac path;
  her voice and her memory fail separately.

## Resume

Step 4 is done and verified; step 5 (auto-blink and idle motion) is the next
build, and most of it is wiring updaters Natori already declares. The real
remaining seam is `attachStream()`, which is written and unused — the prototype
is still driven by a test overlay, not by her voice.
