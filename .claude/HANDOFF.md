# HANDOFF — Arisu web (2026-09-15, night)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

- **Deployed** (lain `ee11af6`, architect active): the web page no longer puts
  the speech service's raw error text in red across the top; errors go to the
  console and `/arisu/diag` as `reason: page-error`. Buttons: accent = on,
  grey = off, mute and held mic never red, nothing grows. A Live2D face that has
  not drawn after 12s posts `{arisu:'no-face'}` to the parent, which swaps in
  the portrait; no text over her face any more. Backlog: three steps ticked.
- **arisu repo** `790cc58`, pushed: expressions + gestures for Hiyori, Rice,
  Mark, Wanko; diag fallback; verify fixes. Host-override case was a broken
  test (bare object as a script = SyntaxError) and passes now; y -0.12
  threshold relaxed to > 0.53.
- **lain has deliberate local changes NOT committed**: the four rigs'
  `.model3.json` + `exp/` dirs, `arisu-avatar.js`, `arisu-face.js`. They wait
  for the four failing cases below. Do not `git add -A` in lain.
- Stray " 2" duplicates (Finder copies, all older) moved to the Trash.

## Open

1. **iPhone: model and image do not load.** Not reproduced: live bundle parses,
   headless Chrome at phone size draws Haru live and locally. Safari-only.
   After this deploy the phone should show the portrait and post a report.
2. **Verify: 4 of 25 fail** — Hiyori/Wanko/Rice expression names and the
   Natori gesture count. The hooks are in the bundle and the probe waits for
   the model, so the cause is open. Last verify run was pre-y-fix: 20/25.

## Next steps

1. Oscar opens https://architect-server.tailaa64e9.ts.net:8443/arisu/ on the
   work iPhone; then `curl -s https://architect-server.tailaa64e9.ts.net:8443/arisu/diag`
   and read the `no-face` / `page-error` report (UA, gl, errors). In memory:
   read it before any lain restart.
2. With the screen unlocked: `python3 live2d/tools/serve.py 8899 ../lain` then
   `live2d/tools/live2d-verify.sh`; for a failing case run
   `node live2d/tools/live2d-probe.mjs '<url>?model=Hiyori&probe=1' 30000` and
   read `probe.hooks`, `probe.expressions`, `probe.gesture`.
3. When 25/25: commit the lain local Live2D changes and deploy (deploy-lain).

## Gotchas

- **Never edit live2d-verify.sh while it runs**: bash reads the script as it
  goes, and an edit mid-run broke the whole run with a syntax error.
- Headless Chrome will not start with the Mac screen locked ("Chrome never
  came up").
- The Backlog MCP tools return the whole project (~76k chars); the edit still
  lands. Grep the saved result to confirm.
- Never make `ossskkar/lain` public (Cubism Core). Run `patch-sdk.sh` after a
  fresh SDK. A glue change is copied into `lain/arisu/live2d/` as-is.
- `/arisu/diag` and the command queue are in memory: a lain restart empties them.
- Oscar's Chrome has acceleration off; use Safari. Mac muted = silent Arisu.

## Resume

"Read arisu/.claude/HANDOFF.md and the Arisu Backlog entry, then read
/arisu/diag for the iPhone report."
