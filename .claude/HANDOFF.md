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

## Her face can be a voice visual — built, installed, waiting on his pick
`native/Arisu/VoiceVisual.swift` draws **all five spheres he shortlisted** —
halo, bubble, groove, trail, ribbon — as a SwiftUI `Canvas` in the dashboard's
skin (bloom, scanlines, vignette; the state colour is the only state cue, his
own `pet.level` is the movement, with a slow breath under it so a waiting face
is not a still one). **Settings ▸ Face** picks one; **Portrait** keeps the
still and the Live2D model exactly as they were, with the model grid and the
Live2D toggle hidden unless Portrait is chosen. Default: **ribbon**.

Why all five rather than one: he was away and the pick was the only thing
blocking, so the reversible choice was to ship the lot behind a picker and let
him choose on the device. Overturning it is deleting four cases of an enum.

Checked in the iPad simulator, all five draw (screenshots were taken from a
temporary build that opened in voice mode; that patch is reverted). The
install to his iPad landed; **the launch did not, because the iPad is locked**
— it opens on the new build next time he taps it.

The 67 mockups stay in `native/voice-visuals.html`. Keep the Swift and the
HTML in step, or the next round of picking is done against the wrong picture.

## Also done while he was away (2026-09-29)
- The spheres breathe at rest (an amplitude floor) — a still face read as a crash.
- `ChatScreen` (the web-view chat) and `newVoiceConversation` are deleted: both
  went unreferenced when the chat became native and the composer took over.
- `deck.py selftest` now covers `front_group`, including the two empty answers
  (an app he never mapped, and no app at all) that mean "leave the rail alone".

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
1. He opens **Settings ▸ Face** on the iPad and picks a sphere; delete the
   four he does not want, or leave the picker if he likes having them.
2. Watch one real call with it: the spheres are untested against a live
   `pet.level` and against 60 fps on the 2020 iPad Pro. If it drops frames,
   the first thing to cut is the bloom (`glow()` — two strokes per path).
3. `native/Arisu/Chat.swift` history sheet is read-only on purpose; if he
   wants to resume an old thread the desk needs an endpoint for it.

## Resume
Read this file. The app on his iPad is current; the open question is only
which sphere he keeps.
