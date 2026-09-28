# Handoff — the iPad app: one screen, and her new face (2026-09-28)

Everything below is **the iPad app only** (`native/`). The web face and
`lain/arisu/chat.html` are the phones' and are not being changed.
State and progress: Backlog project **Arisu**.

## State — all built, installed on the iPad, pushed
- **Chat is native.** `native/Arisu/Chat.swift`: `Chat` (model, talks to
  `GET/POST /arisu/chat`, `/arisu/chat/new`, `/arisu/history`) and `ChatPane`
  (thread + composer) and `ChatHistory`. The web view is gone from the app.
- **Composer is the navigation.** Send, and Voice — Voice draws the hologram,
  unmutes and starts the call; a keyboard button under her comes back and ends
  it. 5 minutes of silence closes the room (`closeQuietRoom`).
- **Deck**: left, `arisu.deckFraction` of the width (drag the seam), keys 72pt
  at the bottom, swipe to change group, apps strip above the tabs, and the rail
  follows the Mac's frontmost app (`GET /deck/front`, `lsappinfo`).
- **One skin**: `native/Arisu/Skin.swift` — lain's palette, radius 10,
  `IconButton`, `Skin.mono`. Title (magenta, flickering) spans both panes.
- **lain**: `history.merged()` folds spoken lines into the typed thread with
  `via: "voice"`; deployed to architect, suite 353 (1 pre-existing failure in
  `test_reader`, a date test, not ours).

## In flight — her face becomes a voice visual
He wants the avatar/portrait in voice mode replaced by an animated voice
visual. **67 animated mockups** live in `native/voice-visuals.html` — open it
in a real browser (not a preview pane). He has liked, in order of narrowing:
5, 9, 10, 14 → 33, 27, 28, 25 → then "sphere, lain cyberpunk look", which is
**63–67** (halo / bubble / groove / trail / ribbon sphere). **He has not named
the final number yet — ask him before building.**

### How to build the chosen one
1. New `native/Arisu/VoiceVisual.swift`: a SwiftUI `Canvas` inside
   `TimelineView(.animation)`, porting that panel's draw function from the
   HTML (same maths, `GraphicsContext` instead of 2D canvas).
2. Inputs: `amplitude` from `live.level` (0…1, already smoothed) or
   `pet.level`, and the state colour from `ContentView.phaseColor`
   (idle indigo / listening green / thinking magenta / speaking cyan).
3. Draw it where `ContentView.face` (line ~501) draws `FaceView`. Keep
   `FaceView` and put the choice behind a Settings switch rather than deleting
   the portrait.
4. Build, install and relaunch on his iPad — no Xcode needed:
   `xcodebuild -project native/Arisu.xcodeproj -scheme Arisu -configuration Debug -destination 'platform=iOS,name=iPad' -derivedDataPath /tmp/claude-501/arisu-dev -allowProvisioningUpdates build`
   then `xcrun devicectl device install app --device 085B9100-31D5-5A2D-B44C-82D143A30ACA <path>/Arisu.app`
   and `xcrun devicectl device process launch --device 085B9100-31D5-5A2D-B44C-82D143A30ACA --terminate-existing com.oscar.arisu`.
   He wants a deploy after every visible change, not one at the end.

## Gotchas
- The app's remote is `ossskkar/bender`; `git push origin HEAD` works now.
- The Mac deck is `arisu/deck/deck.py` on :8887, launchd
  `com.oscar.arisu-deck`; its live store is
  `~/.local/share/arisu-deck/buttons.json`, the repo's copy is only the seed —
  edit **both** or the change does not show. `launchctl kickstart -k gui/501/com.oscar.arisu-deck` to restart.
- Use `lsappinfo`, never AppleScript/System Events, for anything about the Mac:
  a pending Automation consent hangs that server inside the syscall.
- `/deck/app` only opens apps named in `buttons.json` — it is a tailnet socket.

## Next steps
1. Ask him which mockup number (63–67 are the current favourites).
2. Build it as above, install, iterate on his verdict.

## Resume
Read this file, open `native/voice-visuals.html` in a browser, and ask him for
the number.
