# HANDOFF — Arisu web (2026-09-15, late night)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

- **iPhone face fixed** (lain `513ffb1`, live). It was slow, not broken: the
  work iPhone gets ~80–200 KB/s from the desk and every face file was served
  `no-store`, so each visit re-downloaded ~4 MB (Mao's 3 MB texture: 36 s).
  `/arisu/live2d/` is now `no-cache` (revalidate, 304 with no body). Oscar
  measured: first visit ~1 min, next visit ~3 s in Safari. Backlog step ticked.
- **Portrait fallback** (lain `224884c`): only when WebGL is missing or nothing
  has drawn in 60 s. The earlier 12 s version aborted downloads in flight,
  which is what the "Load failed" on every shader in the first report was.
  `/arisu/diag` reports now carry per-file download times (`resources`).
- **Web error line and buttons** (lain `ee11af6`): no raw service errors on
  screen, nothing red, accent = on / grey = off. Three Backlog steps ticked.
- **arisu repo** pushed: expressions + gestures for Hiyori, Rice, Mark, Wanko;
  verify fixes (host-override case passes; y threshold relaxed).
- **lain has deliberate local changes NOT committed**: the four rigs'
  `.model3.json` + `exp/` dirs, `arisu-avatar.js`, `arisu-face.js`. They wait
  for the failing cases below. Do not `git add -A` in lain.

## Open

1. **Verify: 4 of 25 fail** — Hiyori/Wanko/Rice expression names, Natori
   gesture count. Hooks are in the bundle and the probe waits for the model,
   so the cause is open. Last run 20/25 (y fix not yet re-run).
2. Why the work iPhone link is so slow (direct on home Wi-Fi) — maybe the MDM.
   Caching makes it matter only on the first visit.
3. First visit is still ~1 min of blank face; showing the portrait until the
   model draws would cover it.

## Next steps

1. With the Mac screen unlocked: `python3 live2d/tools/serve.py 8899 ../lain`,
   then `live2d/tools/live2d-verify.sh`; for a failing case
   `node live2d/tools/live2d-probe.mjs '<url>?model=Hiyori&probe=1' 30000`
   and read `probe.hooks`, `probe.expressions`, `probe.gesture`.
2. At 25/25: commit the lain local Live2D changes and deploy (deploy-lain).

## Gotchas

- **Never edit live2d-verify.sh while it runs**: bash reads it as it goes.
- Headless Chrome will not start with the Mac screen locked.
- Backlog MCP tools return the whole project (~78k chars); the write still lands.
- `/arisu/diag` and the command queue are in memory: a lain restart empties them.
- Never make `ossskkar/lain` public (Cubism Core). Glue is copied as-is into
  `lain/arisu/live2d/`.

## Resume

"Read arisu/.claude/HANDOFF.md and the Arisu Backlog entry, then work on the
four failing Live2D verify cases."
