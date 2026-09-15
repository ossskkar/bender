# HANDOFF — Arisu web (2026-09-16, Oscar away)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

- **Glow colour during calls fixed** (arisu `364255a`, lain `0e2da65`, live).
  `setGlow({loud})` on every audio frame blanked `--state`, so no glow in a call.
- **Live2D verify 25/25** (was 21). Three silent faults, all live (lain `2be1126`):
  expression names registered as `exp_idle.exp3` (nothing asked for that name),
  and a started gesture returns an object, which `>= 0` counted as refused.
- **Loading still** (live): the host shows `live2d/thumbs/<Model>.png` over the
  face until `arisu-diag.js` posts `{arisu:'drawn'}`. Checked headless: shows at
  once, gone 5 s after load.
- lain's deliberate local Live2D changes are now committed; nothing pending.

## Open (all need Oscar's eyes on the phone)

1. Glow changes colour during a call on the work iPhone (Backlog step, open).
2. First visit shows the still, then her (Backlog step, open).
3. Why the phone link is ~80 KB/s (MDM?) — parked, needs the phone.

## Checks

- `node live2d/tools/glow-patch-check.js` — setGlow is a patch (Node).
- `python3 live2d/tools/expression-names-check.py ../lain/arisu/live2d` (no browser).
- `python3 live2d/tools/serve.py 8899 ../lain`, then `live2d/tools/live2d-verify.sh`
  and `node live2d/tools/glow-call-check.mjs '<face page url>'`.

## Gotchas

- **Never edit live2d-verify.sh while it runs**: bash reads it as it goes.
- One headless Chrome at a time; a second one poisons SwiftShader runs.
- Headless Chrome will not start with the Mac screen locked.
- Backlog MCP tools return the whole project (~79k chars); the write still lands.
- The verify output shows only scene fields; for gesture/expression detail run
  `live2d-probe.mjs` on the single case.
- Never make `ossskkar/lain` public (Cubism Core).

## Resume

"Read arisu/.claude/HANDOFF.md; ask Oscar what he saw on the phone for open 1-2."
