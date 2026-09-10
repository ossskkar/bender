# HANDOFF — Arisu (2026-09-10, evening)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

## State

**Deployed. lain is live on architect** with the cast, the cleanup and the
single mind. Verified there: `set_mood` moves the hologram, `think` answers
from his real day, an unknown tool 400s, and the whisper path returns
`source: hermes`.

**She has one mind now, and it is Hermes.** `/arisu/listen` used to run a
second, smaller Arisu — the Messages API on Haiku with its own key, its own
JSON contract and a subprocess bridge onto the lain MCP tools. Whisper mode was
therefore a different pet from mini and full, which were already going through
`hermes.ask`. All three now take the same path, so what she knows no longer
depends on which mode is selected. 300 lines went with it.

**The browser face is deleted.** `index.html`, its assets, `preview.html` and
`deploy.sh` (which copied it into the retired Mac HUD), plus the three lain
routes only it used — `heard`, `idle` and `voice`. The app calls seven routes
and nothing else.

**Hermes itself moved to Claude Sonnet 5** on 2026-09-10, which is the actual
answer to "she feels not so smart". Detail in `homelab/README.md`.

**Her face is a live renderer.** The `signal-face` animation he downloaded, in
a `WKWebView`. Five states of its own — idle, listening, thinking, speaking,
asleep — with blinks, gaze drift, breathing, and a jaw band driven by
amplitude. `ContentView.Phase` already said four; the fifth is the mic being
down. Verified on an iPad Pro simulator.

**A mute button.** Third control that is not the other two: the waveform ends
the conversation, the record dot is push-to-talk, mute keeps the session and
her context while no audio leaves the device. Turn detection goes off while
muted, or unmuting makes her answer a sentence nobody said.

**There is a cast now.** `persona.py` holds a set of characters and which is
active; each has an identity (`prompt`), the three dials, a voice, a face and
his note. `load()` still returns one settings dict, so nothing downstream
changed. `POST /arisu/characters` does switch, add, edit and delete in one
call. The picker is at the top of the settings sheet.

**Faces are generated.** `faces/` holds `renderer.js` once, plus
`portraits/<id>.png` and `<id>.json` per character; `python3 faces/build.py`
writes one self-contained page into `native/Arisu/Face/`, which is a folder
reference, so a new character needs no Xcode edit.

## Decisions & open questions

- **Chopper's portrait is provisional and he is replacing it.** The image he
  sent was a video screenshot: wide, low contrast, and standing in front of a
  cloudy sky. It builds and reads clearly now, but he said on 2026-09-10 to
  forget it and that he would upload a better format. Do not tune it further —
  redo the landmarks and the backdrop when the real one lands.
- **Open, and his: Chopper's voice.** `shimmer` was picked blind. Voice is his
  taste, the same as `coral` was.
- **Only the identity swaps.** Speech rules, tool rules and the facts about his
  day are assembled around a character and cannot be replaced from the phone.
- **Open, unchanged: the paid Gemini key.** Detail in `homelab/README.md`.
- Generated face pages are committed. Build output in git, deliberately: the
  bundle needs them and there is no build phase.

## Next steps

1. **Chopper's better portrait, when he sends it.** Save it as
   `faces/portraits/chopper.png`, then `python3 faces/grid.py chopper`, read
   the eye and mouth centres off the grid into `faces/chopper.json`, and
   `python3 faces/build.py chopper`. Guessing the landmarks gives a face that
   blinks beside its own eye. Drop `backdrop` from the config if the new one is
   already on a plain ground.
2. **Build and install on the iPad**, then check the picker switches face,
   voice and manner together, and that she now answers from the graph — ask her
   where she has travelled.
3. **Check `set_mood` actually moves her.** It errored on every call until
   today, so nobody has ever seen the hologram change mood from a realtime
   turn. If it still does not move, the fault is now in the app or the model,
   not the route.
4. Watch the battery. A web view for a face is a real cost; the algorithm
   would port to a Metal shader if it matters.

## Gotchas

- **An uncommitted change of his sits in `faces/renderer.js`** — a per-character
  `FILL` that widens her to 0.98 of the screen. Left alone deliberately; it is
  his in-flight work, not part of the cleanup.
- **Whisper mode leaves the hologram where it was.** The deleted JSON contract
  used to carry mood and action out of every turn; only the realtime model sets
  them now, through `set_mood`.

- **A `file://` image taints the canvas** and `getImageData` then throws, which
  is the whole renderer. Portraits are inlined as data URIs. `build.py` does it.
- **A transparent PNG's clear pixels carry junk colour**, handed back
  unpremultiplied. Her first portrait rendered as a field of noise with a
  head-shaped hole. `build.py` flattens onto black.
- **The canvas sizes itself once at mount, then only on a window resize
  event.** A web view's first layout fires no such event, so it stayed 1x1 and
  drew a perfectly running nothing. A `ResizeObserver` on the stage fixes it.
- **A character switch must re-mint the session.** Identity and voice are baked
  in at mint time.
- **A portrait is fitted to the render buffer at build time, and that is why
  characters are lit at all.** The renderer samples into a 300px-wide buffer.
  Arisu's portrait is 532 across, barely a reduction; Chopper's was 1386, and
  the browser's bilinear downscale averaged his four-pixel outlines away to
  nothing. He was not badly lit, he had been sanded smooth before the renderer
  saw him. Lanczos plus an unsharp pass, once, at build time.
- **The backdrop cutter needs its gradient guard.** With only a local colour
  tolerance the fill walked the anti-aliased outline into him and erased him
  entirely — every cel-shaded fill is locally uniform once you are inside. It
  may not enter a pixel sitting on a strong gradient; a drawn outline is a
  ridge, and a ridge is what stops it.

## Resume

Brief as: the face and the mute button are done and verified in the simulator,
both characters build and ship in the bundle, and the cast is not deployed.
Chopper is drawn from a provisional screenshot he is replacing. Nothing is
blocked — the next move is his: send the better Chopper image, or say when to
deploy lain.
