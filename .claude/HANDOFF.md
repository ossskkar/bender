# HANDOFF — Arisu (2026-09-12)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

Second half of this session ran under `away` — decisions were made for him
rather than asked. **Every one is listed below and every one is cheap to
overturn.**

## State

**Everything below is committed and pushed.** arisu on `origin` only — there is
no `architect` remote here. Nothing in lain was touched.

**Steps 4, 4b and 5 are done and verified.** Her audio drives the mouth, her
five states drive Natori's expressions, and the page exposes the exact
`window.avatar` interface her clients already call.

**Auto-blink and idle motion turned out to be free.** The Cubism SDK already
runs eye blink, breath, physics, pose and a random idle motion. Measured: two
blinks in twelve seconds with head angle, body angle and breath all moving. No
code was needed, so step 5 became the expression layer instead.

**The portrait renderer is still what ships.** `faces/renderer.js` is untouched.
This remains a parallel prototype.

**The full account, with every measurement, is in `LIVE2D.md`.** Read that, not
this.

## Decisions made without him — overturn any of these cheaply

- **The mouth runs off an expander, not a fixed gain.** Real speech measured
  0.87 at its quietest against a 1.74 peak, both above where `ParamMouthOpenY`
  clamps, so a gain leaves the mouth hanging open. Half the running peak counts
  as closed. A tracked running minimum was tried first and converges far too
  slowly to use inside one utterance. Knob: `FLOOR_RATIO`.
- **Expressions were picked by reading each `.exp3.json`, not by name.** `Smile`
  is the obvious pick for listening and is wrong — it closes the eyes. `Sad` and
  `Angry` reshape `ParamMouthForm` and stay away from speaking.
- **Asleep forces the eyes shut in the hook** rather than trusting `exp_05`,
  because the blink updater writes the same parameter on its own schedule.
- **Host-fed amplitude is NOT expanded.** The browser client injects a synthetic
  0.10-0.26 envelope when Safari hands back a silent analyser; expanding that
  would floor it to zero and freeze the mouth in exactly that case.
- **`nod` is deliberately unmapped.** It is a head movement, not an expression,
  and faking it from `TapBody` would fight the idle motion queue.
- **The `__arisuParam` debug probe stays.** Read-only, inside the gitignored SDK
  tree, and the only way to see what the rig is doing.

## Parked, and why

- **Packaging Live2D as a real lain face.** Blocked on a licence question, not a
  technical one. The client reaches the face through `contentWindow`, so the
  page must be same-origin, which means the built bundle — **including
  licence-gated Cubism Core** — ships inside lain. `ossskkar/lain` is private but
  `ossskkar/bender` is public, which is why this repo gitignores the SDK and why
  the answer cannot just be copied across. His call. The adapter is written and
  proven, so what remains is a build step and an iframe `src`.
- **Step 6, buying the character.** Costs money.

## Next steps

1. **Decide whether the built Live2D bundle may live inside lain.** Everything
   downstream waits on it and nothing else does.
2. Try the five state buttons on the iPad and say whether the expressions read
   right. They were chosen from parameter values, never seen in motion.
3. Step 6 — choose and buy the real character, checking each listing for app
   use, modification and AI learning.

## Gotchas

- **`requestAnimationFrame` stops dead when the page is not visible**, and a
  hidden browser pane counts. The symptom is `__arisuMouth` staying `undefined`
  with a clean console and every asset at 200. For headless checks, shim
  `window.requestAnimationFrame` onto `setTimeout` from the console — never in
  the page.
- **`patch-sdk.sh` used to skip silently.** It tested one marker string, so any
  later addition to a block was dropped without a word, and it looked exactly
  like new code failing to load. It now uses sentinel comments and replaces
  blocks wholesale. Running it twice is a no-op. **Run it after unpacking a
  fresh SDK, or nothing Arisu adds exists.**
- **`value()` advances its own smoothing.** Exactly once per frame.
- **Cubism cross-fades expressions over ~880ms each way.** A reaction shorter
  than about two seconds reverts before it arrives.
- **Do not use the Vite dev server for anything on the iPad.** Its HMR socket
  cannot reach back through the tailscale proxy and reloads the page every few
  seconds. Build and serve `dist`.
- **The `CubismWebSamples` GitHub repo is a trap.** Neither Core nor its
  Framework submodule. Only the licence-gated SDK zip builds.
- Unchanged: arisu has only `origin`; `arisu/deploy.sh` is the dead Mac path;
  her voice and her memory fail separately.

## Resume

Lead with what he can overturn, not with what was built — he was away. The one
thing genuinely waiting on him is whether the built Live2D bundle may live
inside lain; everything downstream is blocked on that and nothing else is.
