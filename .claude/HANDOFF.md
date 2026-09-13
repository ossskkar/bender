# HANDOFF — Arisu (2026-09-13)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

Clean trees, all pushed. arisu head is this handoff commit (work in `0d40968`,
`52dc1e9`, `84559eb`, `0c74410`, `2678d96`). lain deployed to architect at
`414749a` (web UI `a3b8540`, filler fix `4a6c297`, diag `2448f0f`).

Built and verified in headless Chrome / simulator build:
- **Web client is the main surface** (`lain/arisu/index.html`): the iPad's
  buttons, a settings panel for `?c=` (manner, voice, notes, name, who they
  are, new/delete; Arisu undeletable), face picker as a thumbnail grid.
- **Eight Live2D samples ship**; any character wears any (`?model=`, or the
  saved `persona.model`). Arisu defaults Haru, Chopper Natori.
- **`/arisu/diag`**: face page reports if it failed to draw; each web call
  reports its events and peak amplitude on hangup.
- **iPad app**: Settings > Face > Live2D face (off by default), loads from the
  desk, uses the saved model, falls back to the portrait. Builds; never launched.

Built, unproven (needs a paid call): mouth moving in Safari (now keyed on
`output_audio_buffer.started/stopped`), and fewer filler openers (THINK
description no longer says "say a short line first").

## Decisions & open questions

- Buying a character dropped; the eight bundled samples are the cast.
- iPad Live2D loads over the tailnet: Cubism Core cannot live in public arisu.
- Web page has no room buttons: it is not a room member, would break one-ear/one-mouth.
- Open: Oscar has not yet picked each character's face; "Play sample" not on web.

## Next steps

1. Oscar calls her in Safari at https://architect-server.tailaa64e9.ts.net:8443/arisu/
   (waveform button), asks two questions, hangs up.
2. Read the call report: `curl -s https://architect-server.tailaa64e9.ts.net:8443/arisu/diag`
   — expect `output_audio_buffer.started` and `maxAmplitude` > 0. Mouth still
   shut: compare with `analyserHeard`. Fillers still there: check
   `ssh architect 'grep said /tmp/arisu-face.log | tail'`.
3. Tick "Her mouth moves in Safari" / "no stock openers" in the Backlog if proven.
4. iPad: install from Xcode, turn on Settings > Face > Live2D face.
5. Money: habit add/remove test; room buttons and Play sample stay parked.

## Gotchas

- Never make `ossskkar/lain` public (Cubism Core). Run `patch-sdk.sh` after a fresh SDK.
- Re-vendor after a face change: build in `arisu/live2d/CubismSdkForWeb/Samples/TypeScript/Demo`
  (`npm run build:prod`), copy `dist/index.html`, `dist/assets/*`, `dist/arisu-*.js`
  into `lain/arisu/live2d/`; a new model also needs a still in `thumbs/`.
- Launching the iPad app mints a paid realtime session at once (`Pet.running` starts true).
- rAF stops in a hidden pane; test in headless Chrome over CDP (`--headless=new
  --use-angle=swiftshader`). The stock SDK `alert()` froze pages; patched out.
- Oscar's Chrome has acceleration off; use Safari. Mac muted = silent Arisu.
- `/arisu/diag` is in memory: a lain restart empties it.

## Resume

"Read arisu/.claude/HANDOFF.md and the Arisu Backlog entry, then check /arisu/diag for his last call."
