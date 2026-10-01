# Handoff — command bubbles, deck wheel, web parity (2026-10-01, afternoon)

State and progress: Backlog project **Arisu**. "I tap a command button over her
voice animation" is in **review** (all steps ticked; brief and AI signals were
heard, seen in the chat history). Brain dump and Pencil are still in review too.

## State
- **Command bubbles** (iPad voice mode, top right, vertical): Today's brief,
  Week review, AI signals (lain `GET /arisu/line?key=brief|weekly|signals`,
  said word for word via `Live.speak`), What's next?, How's my running?
  (put to her as Oscar's turn via `Live.ask`). A tap on her hides/shows them.
  Fixed list in `ContentView.commands` — not deck-editable.
- **iPad look**: voice opens muted; no seam line, no rule under the title bar,
  no rule over either bottom bar; bottom bars 28pt off the edge (= deck keys);
  chat pane inset 10pt so corners meet Record/Deck; title buttons white icon
  on a lit cyan edge (`IconButton.ink`, stroke 0.7).
- **Deck groups** are a wheel (`DeckRail.groups`/`roll`): drag rolls under the
  finger and springs to the nearest; one text size; key area as tall as the
  tallest group. `FlowRow` deleted.
- **Web** (`lain/arisu/index.html`, `eb4f14e`, live): same console look and
  the five bubbles; voice opens muted; `--mono` now defined (it never was).
- arisu `e1ba1b9` pushed; lain `eb4f14e` on both remotes, pulled on architect.

## Open
- Web changes checked only as a static render (chat + voice layout); no live
  call tested on the web. Bubbles' wake path and muted-on-entry unverified there.
- Long group names (CLAUDE-CODE) clip at the wheel's edge until centred.
- Leftover `/var/lib/lain/taps.json` on architect: `sudo rm` is Oscar's.
- Architect `~/lain` still carries someone's uncommitted chat-import work;
  pull with stash/pop (backups `~/lain-uncommitted-2026-09-30/10-01.patch`).

## Next steps
1. Oscar tries the bubbles on the web in Safari (a live call) → fix what breaks.
2. Oscar says done → move the three review journeys to done (`confirmed_by="oscar"`).

## Gotchas
- iPad install: `xcrun devicectl device install app --device 085B9100-31D5-5A2D-B44C-82D143A30ACA <app>` (the short id fails).
- `.claude/launch.json` "lain" points at :8887, which is the deck now — do
  not start it; preview the web page with a throwaway static server.
- Backlog MCP writes return >130k chars; they still land.
- lain restart is Oscar's: `ssh -t architect 'sudo systemctl restart lain.service'` (static files need no restart).

## Resume
"Read arisu/.claude/HANDOFF.md and continue with the next step."
