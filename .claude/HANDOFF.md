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

## Gotchas
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
