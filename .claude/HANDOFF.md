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
- **Broken: Record returns 404.** lain `6e3e4b9` (`server/dumps.py`,
  `/dumps` routes) is pushed to both remotes but **not live**: architect's
  `~/lain` holds someone's uncommitted chat-import work (server.py, chats.py,
  systems/chat.html, tests/test_chats.py, staged arisu/index.html), so
  `pull --ff-only` refuses. Claude was denied the stash/pull/pop.
- Codex and DSH are not installed on the Mac; those buttons go red.

## Decisions
- Record audio is transcribed by architect's whisper-server (never leaves his
  machines); insights are Gemini via `llm.ask`; data in data.json `"dumps"`.
- Per-kind colours on deck keys were tried and reverted at his request.

## Next steps
1. Oscar (or Claude with permission) deploys lain:
   `ssh architect 'cd lain && git stash && git pull --ff-only && git stash pop && sudo -n systemctl restart lain.service && sudo -n systemctl restart lain-mcp.service'`
2. Check `curl -s https://architect-server.tailaa64e9.ts.net:8443/dumps` → `{"dumps": [...]}`.
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
