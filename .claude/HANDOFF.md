# Handoff — one conversation, one screen (2026-09-27)

Voice and chat were two Hermes sessions on two screens. They are one thread and
one screen now. State and progress: Backlog project **Arisu**, journey
*"I switch between typing and talking in one conversation"*.

## State
- **One thread, live on architect.** Every Hermes session — spoken or typed —
  is created seeded with the tail of the one conversation (`history.seed`
  merges the chat log and the voice log on their clocks), and
  `hermes.invalidate()` drops the sessions that did not produce the last line.
  Proven end to end: typed "remember: amber" to `/arisu/chat`, asked through
  `/arisu/tool` `think` (the voice path), got it back.
  `voice_reset`/`chat_reset` → one `reset()`; "new conversation" is one thing.
  lain suite 353 OK. Commits `baf6d94`, `5f2d60c`, `53666c2`, all deployed.
- **One screen, built and checked in the iPad simulator.** `DeckScreen` →
  `DeckRail` (196pt, right, both modes, one group at a time); the chat page is
  a pane beside it loaded with `?chrome=0` so it draws no second masthead; the
  microphone is its own button; the deck button toggles the rail and remembers
  it. Commit `0516b4f` in `arisu` — **committed, not pushed** (its remote is
  `ossskkar/bender` and the push was refused here).
- **The Mac's deck answers nothing**, so the rail is empty. See below.

## Decisions
- **The two transcript renderers stay.** Merging them was in the plan and was
  dropped: subtitles over the room are read from the sofa, the chat page at
  arm's length; one implementation makes one of them worse, and a webview over
  the glow buys nothing the chat page does not already do in Safari.
- **Not one shared Hermes session.** That would put the voice on the chat's
  40-question thread; long threads were 58% of all input on 2026-09-17. The
  seed pays once per `session.create` instead. If she loses the thread, raise
  `hermes.SEED` (16) — never the turn cap.
- Reasoning `low`, measured faster for typed, now applies to the voice too
  (`LAIN_HERMES_REASONING`). Watch for shallower spoken answers.

## Gotchas
- **A TCC-denied `open()` on macOS hangs; it does not fail.** The deck served
  `/` in a millisecond and left every `/deck` waiting forever. Sampling the
  process shows the handler thread parked in `__open`. Moving the store to
  `~/.local/share/arisu-deck/buttons.json` did **not** fix it — the job has no
  file-access consent at all. The repo's `buttons.json` is now the seed.
- The lain backlog API has no `step_set_done` op over HTTP; `step_edit` with
  `done:true` is the one that works.

## Next steps
1. Grant the deck's python file access — System Settings ▸ Privacy & Security,
   for `/usr/local/bin/python3.11` — then
   `launchctl kickstart -k gui/501/com.oscar.arisu-deck` and check
   `curl -s http://127.0.0.1:8887/deck`.
2. `cd ~/Documents/claude-projects/arisu && git push origin HEAD`.
3. Run the app on the iPad from Xcode and use it for an evening.

## Resume
Read this file and continue with the Backlog journey above.
