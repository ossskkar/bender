# HANDOFF — Arisu (2026-09-10)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

## State

**Nothing is deployed. He asked for that** — the iPad was not nearby. Both
repos are committed and pushed to GitHub only. `lain` has **not** been pushed
to the `architect` remote and architect has **not** pulled or restarted, so the
desk is still running the old server.

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

- **Blocked, and his: Chopper has no portrait.** He said an image was
  attached; it was not reachable from this session — not in Downloads, Desktop
  or Pictures. Chopper exists on the desk with a written prompt and voice
  `shimmer`, and falls back to Arisu's face until a picture lands.
- **Open, and his: Chopper's voice.** `shimmer` was picked blind. Voice is his
  taste, the same as `coral` was.
- **Only the identity swaps.** Speech rules, tool rules and the facts about his
  day are assembled around a character and cannot be replaced from the phone.
- **Open, unchanged: the paid Gemini key.** Detail in `homelab/README.md`.
- Generated face pages are committed. Build output in git, deliberately: the
  bundle needs them and there is no build phase.

## Next steps

1. **Get Chopper's picture.** Save it as `faces/portraits/chopper.png`, then
   `python3 faces/grid.py chopper`, read the eye and mouth centres off the
   grid, write `faces/chopper.json`, and `python3 faces/build.py chopper`.
   Guessing the landmarks gives a face that blinks beside its own eye.
2. **Deploy lain when he says so** — `git push architect main`, then pull and
   restart on architect. Until then `/arisu/characters` 404s, the cast fetch
   fails quietly and the picker does not appear. That is what the simulator
   shows today and it is not a bug.
3. **Build and install on the iPad**, then check the picker switches face,
   voice and manner together.
4. Watch the battery. A web view for a face is a real cost; the algorithm
   would port to a Metal shader if it matters.

## Gotchas

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

## Resume

Brief as: the face and the mute button are done and verified in the simulator,
the cast exists end to end but is not deployed, and Chopper is waiting on a
picture. Ask him for the image first — it is the only thing blocking.
