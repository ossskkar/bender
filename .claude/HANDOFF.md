# Handoff — brain dumps + Pencil scribbles proven, app restyled (2026-10-01)

State and progress: Backlog project **Arisu**. Two journeys finished and in
**review**, every step ticked, waiting for Oscar's word to move to done:
"I record a brain dump on the iPad…" and "I pick up the Pencil and scribble…".

## State
- **Record**: iPad → lain `POST /dumps` → whisper on architect → history;
  insights (Gemini via `llm.ask`) confirmed by Oscar.
- **Scribbles** (arisu `0d5c6e9`, `0e1a456`; lain `d595ea7`, live): first
  Pencil touch anywhere opens a PencilKit canvas; SAVE posts a PNG to
  `/dumps/scribble` → `/var/lib/lain/scribbles/<id>.png` + a dumps row with
  `image: true`, shown in the Record history as `// SCRIBBLE`. The page
  persists on the iPad (`Documents/scribble.drawing`) until CLEAR. 2 saved.
- **whisper-server on architect**: user unit `whisper.service` (linger on),
  `~/whisper.cpp/build/bin/whisper-server`, model `ggml-base.en-q5_1`,
  127.0.0.1:20301. lain `7c4b341`: dead ear → 503, the iPad keeps the WAV.
- **Look**: Record/Deck neon style app-wide (arisu `7f87c48`) — `Grid`,
  `Brackets`, `.console()` in `Skin.swift`, `Skin.radius` 0, mono type.
  Voice mode: meter gone, `> LISTENING_` state text in its place.
- **Deck**: keys fill bottom up (`eeda3a8`); blanks in the top row.
- All installed on the iPad; arisu and lain pushed (lain to both remotes).

## Decisions
- Scribbles go to lain beside the dumps, not Photos and not the p100k-data
  repo (images would live in git forever).
- Scribble/Record code lives in `Record.swift` — no pbxproj edit needed.

## Open
- A second SAVE of a persisted page uploads the whole page again (by design
  of "stays until CLEAR"); fine unless Oscar objects.
- Voice mode: the face's dark square hides the grid behind it.
- Architect `~/lain` still carries someone's uncommitted chat-import work
  (chats.py, server.py, chat.html, test_chats.py); backup
  `~/lain-uncommitted-2026-09-30.patch`.

## Next steps
1. Oscar says done → `backlog_journey_status` both journeys → done with
   `confirmed_by="oscar"`.
2. Backlog journey "command buttons over her voice animation" (Today's
   Brief first) — pick the commands.
3. Deck in landscape on the real iPad still unchecked.

## Gotchas
- Pulling on architect: backup patch, `git stash push`, `pull --ff-only`,
  `stash pop` (server.py auto-merges). Restart is Oscar's:
  `ssh -t architect 'sudo systemctl restart lain.service'` — the classifier
  refuses it for Claude. "Connection to architect closed" is normal.
- The simulator cannot make Pencil touches; Pencil paths need the real iPad.
- iPad installs over Wi-Fi (`devicectl … --device 085B9100-…`). The Dell hub
  cannot charge a flat iPad Pro.
- Backlog MCP tools return the whole project (>130k chars) on every write;
  the write still lands — grep the saved file to confirm.
- Stop simulators after screenshots (`simctl terminate`, `simctl shutdown`).

## Resume
"Read arisu/.claude/HANDOFF.md and continue with the next step."
