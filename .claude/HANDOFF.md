# HANDOFF — Arisu (2026-09-16, iPad state colours)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

- **iPad app state colours: done, confirmed by Oscar on the iPad.**
  Idle indigo, listening green, thinking magenta, speaking cyan; same for every
  character (`ContentView.rgb(_:)`). Glow around her silhouette, ground, meter
  and label all wear it. Legend top left, current state lit.
  - Glow = CSS `drop-shadow` on the face page `<body>`, injected by `FaceView`
    on load (`glowCSS`, `data-glow`, `--glow`, `--amp`). Works for the portrait
    and the Live2D page without editing either.
  - Meter = one travelling wave; listening scales it by `Live.micLevel` (his
    mic), so it is a mic light. `level_meter` is gone.
  - Caption raised, 130pt side padding so it clears the control column.
  - Commits 72d385f, ad3d0b0, ca370de, f3d2f88.
- The page-sheet work from an earlier session (`PageSheet`, `ShowPage` in
  Brain/Live) was uncommitted; committed at handoff since it builds and is
  in the build on the iPad.
- Earlier web open items still open: glow during a call on the work iPhone;
  first visit shows the still, then her; phone link ~80 KB/s.

## Decisions

- Base colour is shared by all characters for now (Oscar). Per-character colour
  from the portrait was proposed and deferred.
- Colours picked as best guess; listening moved from white to green because a
  white glow does not read as a colour.

## Next steps

1. Ask Oscar what to do next on the iPad app, or the open web items above.

## Gotchas

- **Install on the iPad from the Mac** (it is paired, id `085B9100-...`):
  `xcodebuild -project native/Arisu.xcodeproj -scheme Arisu -destination 'id=085B9100-31D5-5A2D-B44C-82D143A30ACA' -derivedDataPath <scratch>/dev -allowProvisioningUpdates build`,
  then `xcrun devicectl device install app --device 085B9100-31D5-5A2D-B44C-82D143A30ACA <.app>`
  and `xcrun devicectl device process launch --device ... --terminate-existing com.oscar.arisu`.
- The iPad simulator froze on boot and `simctl openurl` timed out; to check
  CSS in WebKit, a tiny Swift WKWebView snapshot on the Mac works faster.
- Partial-hunk commits with filtered patches split a change across hunks once;
  build the staged tree (`git checkout-index -a --prefix=...`) before committing.
- Backlog MCP tools return the whole project (~80k chars); the write still lands.
- Never make `ossskkar/lain` public (Cubism Core).

## Resume

"Read arisu/.claude/HANDOFF.md and ask Oscar what's next for Arisu."
