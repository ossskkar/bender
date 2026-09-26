# HANDOFF — Arisu (2026-09-26)

*Progress lives in the lain Backlog, project Arisu. Three journeys moved this
session; two are new and sit in **review** waiting for Oscar's verdict on the
real iPad.*

## State — what works

**The app overhaul shipped** (`arisu` d552d2f, `lain` 6530c67 + the viewport
fix). Verified in the iPad Pro 13" simulator against the live desk and the
live Mac.

- **One top row, always visible.** The four voice-only buttons (subtitles,
  conversation, listen-here, settings) left the bottom-right corner and the tap
  that hid them; they are square buttons beside deck / history / new / the
  Voice|Chat switch. Her masthead sits at the same height on **both** screens —
  in Swift on the voice screen, and moved out of the scrolling log into `#top`
  on the chat page. The legend dropped to `padding(.top, 82)` to clear it.
- **The chat keyboard is fixed.** `paint()` set `input.disabled = busy`, which
  blurs the field; a blurred field in a WKWebView cannot be focused back by
  script, and the `input.focus()` calls that followed left it the active element
  so the next real tap did nothing. The field is never disabled now, the
  scripted focus calls are gone, and a `pointerdown` on the prompt row focuses
  it inside the gesture. `interactive-widget=resizes-content` keeps the masthead
  on screen when the keyboard is up.
- **Bubbles or terminal**, one setting (`arisu.bubbles`) obeyed by her subtitles
  and by the chat page, which is told through `?style=`.
- **Two faces.** `arisu3D` (22 entries) and six Live2D samples are gone; Haru
  and Mao remain, Haru hers by default. An unknown saved model falls back to the
  character's default, not to the portrait.
- **Where she stands**: two sliders, on the device (`arisu.faceX/Y`).
- **The deck is new** — `arisu/deck/`, and it is where the macropad went. The
  Mac runs `deck.py` (that project's executor verbatim, harvested with `ast`)
  on `127.0.0.1:8887`, which the Mac's **existing** `tailscale serve :8443`
  rule already proxied to. The iPad draws its 36 buttons grouped, presses them,
  and adds/edits/removes them. `POST /deck/run` takes an **id and never an
  action**. `./deck.py selftest` passes.

## Decisions & open questions

- **Port 8887, not a new serve rule.** The rule existed and pointed at a dead
  port, so the deck needed no change to his machine. Written up in the
  workspace `CLAUDE.md` and in the `deploy-lain` skill, both of which still
  called 8887 dead.
- **`MacropadType.app` keeps its name.** It is the bundle that holds
  Accessibility; renaming means granting it again. Seven of 36 buttons are
  `keys` and call it.
- **Not verified, and only he can:** the software keyboard physically rising on
  the iPad (the simulator has a hardware keyboard attached, so only focus could
  be proven), and the native *terminal* subtitle style, which needs a live voice
  conversation to draw anything.
- **Left alone:** `lain` had `server/server.py`, `server/tap.py`,
  `tests/test_tap.py` dirty and an untracked `systems/systems 2.html` before
  this session. None of it was mine; none of it was committed. The stray
  `systems 2.html` is a version-suffixed file someone should collapse.

## Next steps

1. **His:** load the deck's launchd agent, or the grid goes grey when the
   held-open process dies.
   `cp /Users/oscar/Documents/claude-projects/arisu/deck/com.oscar.arisu-deck.plist ~/Library/LaunchAgents/ && launchctl load -w ~/Library/LaunchAgents/com.oscar.arisu-deck.plist`
2. **His:** rebuild onto the iPad and confirm the keyboard, then the two review
   journeys can be ticked done.
   `cd /Users/oscar/Documents/claude-projects/arisu/native && xcodebuild -project Arisu.xcodeproj -scheme Arisu -destination 'id=085B9100-31D5-5A2D-B44C-82D143A30ACA' -allowProvisioningUpdates build`
3. Unload the old macropad launchd agents once he is happy; they still hold
   8791-8793.

## Gotchas

- **The build expires every 7 days** and the iPad (iPadOS 26.6.2, iPad8,11)
  cannot be jailbroken — TrollStore stopped at iOS 17.0. Checked 2026-09-26.
  The only expiry-free routes are €99/year or Safari over the tailnet.
- **Live2D takes ~10s to render** in the simulator. A blank hologram right
  after launch is not a bug; wait before diagnosing.
- The deck's `press` helper writes to `~/Library/Logs/macropad/type.out`. That
  directory must survive the macropad's removal.
- `xcodebuild -destination 'platform=iOS Simulator,name=...'` fails on the M5
  iPads here; use `-destination 'id=<udid>'`.
- Deploy lain with the `deploy-lain` skill — both remotes.

## Resume

Read `.claude/HANDOFF.md` and the Arisu project in the lain Backlog, then ask
Oscar whether the chat keyboard comes up on the real iPad.
