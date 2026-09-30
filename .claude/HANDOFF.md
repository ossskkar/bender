# Handoff — deck rework, Record panel, history fix (2026-09-30)

State and progress: Backlog project **Arisu** (journeys "I record a brain dump
on the iPad…" and "I pick up the Pencil and scribble on the iPad").

## State
- **Installed on the iPad, pushed** (arisu `f358dd5`):
  - Left half of the screen: **Record on top, deck below**, a quarter each.
  - Deck in rows of three; **sleep pinned bottom right** on every group
    (`pmset sleepnow` on the Mac; the iPad goes to brightness 0 + black cover,
    idle timer released so Auto-Lock takes it; tap wakes).
  - Claude group top-down: away/continue/screenshot, recap/explain/guide,
    clear/handoff/sleep. Apps top-down: Safari/Xcode/Citrix,
    Claude/Codex/DSH, Chrome/Spotify/Terminal.
  - Icons = kind of action (SF Symbols from `DeckAction.symbol`), all cyan;
    labels centred. Long press = explanation (`about` field); press-drag
    reorders keys and apps (saved via `POST /deck`, apps reorder-only).
  - Chat history opens again (the `session` field is an object on the wire).
  - A call Arisu starts herself switches the screen to voice.
- Mac deck (`deck/deck.py`, store `~/.local/share/arisu-deck/buttons.json`)
  keeps `about` and accepts app reorders; restarted, answering 200.
- Skills `/recap`, `/explain`, `/guide` in `~/.claude/skills/`.
- **Record backend live** (lain `6e3e4b9`, `/dumps` → 200). The chat-import
  work on architect was stashed, pulled over and popped back cleanly; it is
  still uncommitted in `~/lain` (backup `~/lain-uncommitted-2026-09-30.patch`).
- Codex and DSH are not installed on the Mac; those buttons go red.

## Decisions
- Record audio is transcribed by architect's whisper-server (never leaves his
  machines); insights are Gemini via `llm.ask`; data in data.json `"dumps"`.
- Per-kind colours on deck keys were tried and reverted at his request.

## Next steps
1. (done) lain deployed, `/dumps` answers. whisper-server now runs ON architect
   (user unit `whisper.service`, `~/whisper.cpp`, 127.0.0.1:20301; it was only
   ever on the Mac before, so the first retry read as silence and was deleted).
   lain `7c4b341` makes a dead ear a 503 (iPad keeps the WAV) -- needs Oscar's
   `sudo systemctl restart lain.service` to be live.
   Deck restyled in the Record panel's look (arisu `2119e4e`), installed.
2. Whoever owns the chat-import work on architect commits it.
3. Oscar presses [RETRY] on the kept recording, then [RUN ANALYSIS].
4. Deck in landscape: only checked in portrait (simulator would not rotate);
   confirm keys fit the bottom quarter on the real iPad.
5. Pencil scribble idea: see its Backlog journey; decide where saves go first.

## Gotchas
- lain test `test_reader.test_a_stale_feed_is_not_read_as_todays_news` fails;
  unrelated to this work.
- New Swift files must be added to `project.pbxproj` by hand (explicit refs).
- iPad install: `xcodebuild … -destination id=085B9100-31D5-5A2D-B44C-82D143A30ACA`
  then `xcrun devicectl device install app --device <id> <.app>`.

## Resume
"Read arisu/.claude/HANDOFF.md and deploy the Record backend."
