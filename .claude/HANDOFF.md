# HANDOFF — Arisu (2026-09-16, conversation fixes)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

- **Plan-first turns: deployed on the web (lain 5a8ad90) and installed on the iPad (arisu 8e83867).**
  Every turn is a text-only response ("plan"); its text is deleted, and one audio
  reply with `tool_choice: none` is asked for once its work is back.
  - Fillers ("let me think…") can no longer be heard: the live-API probe showed the
    plan writing that line as text and the only audio being the answer.
  - Only the newest question's `think` gets a reply; a late one is logged
    `superseded` (web voice log) / `ev: superseded` (iPad face log).
  - Quiet: no reply is asked for while hushed; iPad now has quiet too.
  - Barge-in back on (`LAIN_ARISU_INTERRUPT` default 1; clients set it on connect).
  - Timing per answered turn: plan / think / voice ms (voice log `kind: timing`; face log `ev: timing`).
  - Hermes `SPOKEN` prefix: act on a change and say what changed, no asking (deletions
    excepted); never name tools/files. She rarely says his name.
- His own lines are now logged as `kind: heard`, not `answer`.
- Rules + tests: `lain/arisu/arisu-voice.js`, `lain/tests/test_arisu_voice.js`. iPad mirror in `Live.swift` (no tests).

## Open — needs Oscar's ears

Stale answer never heard; one-word answer heard first time; quiet holds; go = done;
no internal names; talking over her works and she does not cut herself off.

## Decisions

- Greetings pay ~0.5 s extra (plan, then speech). Accepted to kill fillers structurally.
- An "hm" with no tool while think is out waits for that think (no second reply).
- Group room mode unchanged: the desk still asks via `answer()`.

## Next steps

1. Oscar talks to her; read `ssh architect tail -50 /var/lib/lain/arisu-voice.jsonl` and the face log for `timing`/`superseded`.
2. If she cuts herself off: set `LAIN_ARISU_INTERRUPT=0` in lain.service AND flip `interrupt_response` in `index.html` applyInput and `Live.swift` applyInput.
3. Latency journey step 1: split one slow reply using the timing lines.

## Gotchas

- Install on the iPad: see the previous build commands (xcodebuild with `id=085B9100-31D5-5A2D-B44C-82D143A30ACA`, `devicectl device install app`, `process launch --terminate-existing com.oscar.arisu`).
- Response kinds on the web come from the `asked` queue in order; audio responses echo no metadata.
- Backlog MCP tools return ~80k chars; POST `/backlog` ops directly instead.
- Never make `ossskkar/lain` public (Cubism Core).

## Chat bubbles (2026-09-17)
- His bubbles match hers (glass, outline + text only) in the legend's thinking magenta rgb(255,56,199); web (lain 2eb633f..aacd35b) and iPad app (installed via xcodebuild + devicectl). iPhone app not rebuilt.
- architect's lain checkout carries someone's UNCOMMITTED glow edits (arisu/index.html, cues.js, live2d/index.html, title-check.html). Deploys there need stash / pull / stash pop.

## Tap to show controls (2026-09-17, verified by Oscar)
- iPad app (f5bde79): fold button removed; legend + buttons start hidden, a screen tap toggles them. Settings sheet moved to body so hiding never closes it. iPhone app and web unchanged.

## Resume

"Read arisu/.claude/HANDOFF.md, then read the voice log from Oscar's last conversation with Arisu."
