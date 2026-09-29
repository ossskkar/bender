# Handoff — one screen on the iPad, and the same screen on the web (2026-09-29)

The iPad app (`native/`) and lain's `/arisu/` now do and look like the same
thing. The deck is the iPad's alone and is not on the web, on purpose.
State and progress: Backlog project **Arisu**.

## State — built, installed on his iPad, deployed to architect
- **One screen, both places.** The typed thread is the page; Send and Voice sit
  by the text box; Voice draws her and opens the microphone; a keyboard button
  under her comes back and ends the call; 5 minutes of silence closes the room.
  Past conversations are a panel in the same screen (web) / a sheet (app).
- **Her face can be a voice visual**, ten of them, in `native/Arisu/VoiceVisual.swift`
  and `lain/arisu/sphere.html` — the same motion table in both.
  Spheres: halo, bubble, groove, trail, **ribbon (default both places)**.
  Flat: ring, liquid, lissajous, bubbles, aurora.
  **Colour says which state, movement says what she is doing**: idle breathes
  (5.5 s, quick in, long out), listening pulls waves inward, thinking spins
  fast and jitters, speaking pushes waves outward on her own level.
- **Portrait is still there** — Settings ▸ Face, with Live2D and the models
  untouched. On the web it now saves as `portrait` rather than as empty.
- **Where she stands** moves the drawn face: app Settings, and a web section
  kept per device in localStorage.
- **Deck (iPad only)**: left, draggable seam, keys and application buttons the
  same 72pt button, swipe between groups, the rail follows the Mac's frontmost
  app, and the Claude group now carries away / homelab / model / omni.
- lain suite 357, with one pre-existing failure (`test_reader`, a date test).

## The look, settled 2026-09-29
- **Palette lifted** because the first one was unreadable on the iPad at full
  brightness: magenta `#FF5C9E`, ink `#A3B5D9`, "off" white at 0.45, panel
  fills at 0.08. The title is 19pt on a lit row, and its flicker dips to
  45–75% — a dip to 15% read as a fault, not as a tube.
- **One colour rule**: she is cyan, he is magenta, in bubbles and in terminal,
  in both modes. Terminal puts every line at the left margin with `>` on his.
- **Bubbles or terminal is two preferences**, one per mode.
- **Settings ▸ Face** is a grid of moving tiles (`FacePreview`), each cycling
  the four states. **Settings ▸ The animation** draws the chosen face with
  Size, Glow and Pace on it. The old glow sliders show only for Portrait —
  they never reached a drawn face.
- **The room's bar is the chat's bar**: History · New · Subtitles · her level ·
  Mic · Keyboard. The legend of coloured dots and the floating circles are
  gone; the bar says the state in words.
- **The deck's application buttons carry the real app icons**
  (`GET /deck/icon`, sips on the bundle's .icns, cached on the Mac), and a
  press colours the button — cyan running, green worked, red failed.
- Checked in the simulator: chat, the face grid and the animation preview all
  draw as intended (screenshots under /tmp/claude-501/mock/ui-*.png).

## Gotchas
- **A `const` in its temporal dead zone throws even on `typeof`.** The web
  page broke twice this way (face position, then the face dials); declare
  shared state above everything that reads it.
- **The browser pane is hidden, so rAF is paused and layout is 0×0 there.**
  Canvases cannot be judged by screenshot in it; drive the draw functions
  directly (`SHAPES[name](m, w, t, a)` on a resized canvas) and count ink.
- Simulator screenshots need ~6 s after launch or you photograph the splash.
- A launch on his iPad fails while the iPad is locked; the install still lands.
- The deck's live store is `~/.local/share/arisu-deck/buttons.json`; the repo's
  copy is only the seed. Edit both.
- `lsappinfo`, never AppleScript, for anything about the Mac.

## Next steps
1. He picks a face on each device (Settings ▸ Face) and says which stays.
2. Watch one real call: the visuals are untested against a live `pet.level`
   and against 60 fps on the 2020 iPad Pro. If it drops frames, cut the bloom
   (`glow()` draws each path twice).
3. `chat.html` is now only the phones' fallback; if he wants, fold it into
   `index.html` and redirect.

## Resume
Read this file. The app on his iPad and the page on architect are both current.
