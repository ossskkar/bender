# HANDOFF — Arisu (2026-09-09)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

## State

**Her mind is the whole of Hermes, through one tool.** The realtime session is
minted with two: `set_mood`, her body, and `think`, her mind. `think` was
called `ask_hermes` for one afternoon and that name was the bug — the model
narrated it and treated Hermes as a third party in the room. It is now
described as her own memory, with a rule never to name where an answer came
from. `lain/server/hermes.py` holds one `hermes serve` conversation open.

**She remembers, and it is verified.** An instruction put through `think`
reaches Hermes' `USER.md` on architect. Tested by planting "call me Fish",
restarting lain to force a brand new session, getting Fish back, then removing
it. Her instructions now say she remembers, because she was claiming otherwise.

**Personality is data, not a deploy.** `lain/server/persona.py` holds three
dials (warmth, playfulness, brevity), a voice and a free-text note in a file on
architect; `GET/POST /arisu/persona`. Folded in at mint time, so a change lands
on her next connection. Identity and honesty stayed in code deliberately — a
slider cannot reach her tools, her memory, or the rules about his data. She is
warm now, not sardonic, and no longer uses nicknames.

**The app was reworked.** Four bare icons stacked up the right edge, no
capsules: captions, conversation (waveform in a circle), hold-to-talk (record
dot), settings. The model picker is gone. A four-state indicator says who is
doing something, in colour — he is white, she is cyan, thinking is magenta —
across the meter, a word, and the light she stands on. Settings sheet with the
dials, a voice picker and **Play sample**.

**Push-to-talk works.** Tap the record dot to close the open mic; hold it to
speak one turn, let go to commit. Turn detection is switched off over
`session.update` while armed, or the burst on release is answered twice.

**Fixed this session:** barge-in (`response.done` means the *server* stopped
sending, not that she stopped being audible — `flush()` was gated on the flag
those events cleared); double replies (semantic VAD eagerness `auto` cut him
off mid-sentence, and `set_mood` was asking for a second response); a stuck
"thinking" (a flag that could never come back down, now a count); the filler
line before every answer, which he found grating.

**Unverified:** everything since his last "that works" — Play sample, the bare
icons, the no-filler rule, the thinking count. All built, installed on the
iPad, and pushed; he had not reported back.

## Decisions & open questions

- **Voice is `coral`, chosen blind.** He asked for the film *Her*; taste is his.
- **Preview goes through her own session,** not `audio/speech` — the OpenAI key
  is restricted and lacks `api.model.audio.request`. Widening it is his call
  and is not needed.
- **Open, and his: a paid Gemini key.** A turn is 10–40s and every free lever
  was tried and reverted. Detail in `homelab/README.md`.
- `brain.debug` stays in `Live.swift` for now — `/tmp/arisu-face.log` on
  architect is what identified the barge-in cause and the double replies.

## Next steps

1. **Ask him what is still wrong.** Four changes are installed and unreported.
2. Build and install after any change — he never does it:
   `cd arisu/native && xcodebuild -project Arisu.xcodeproj -scheme Arisu -configuration Debug -destination 'id=085B9100-31D5-5A2D-B44C-82D143A30ACA' -allowProvisioningUpdates build`
   then `xcrun devicectl device install app --device 085B9100-31D5-5A2D-B44C-82D143A30ACA <DerivedData>/Build/Products/Debug-iphoneos/Arisu.app`
3. `conversation.item.input_audio_transcription.failed` — switched to
   `gpt-4o-mini-transcribe`; confirm his half of the transcript now appears.

## Gotchas

- **Anything minted is fixed for the session.** Voice and instructions cannot
  change on a live socket; `Live.reconnect()` is the only way. This is why
  changing the voice looked broken.
- **A response asking her to read a line gets thought about instead.** She is
  told to `think` every turn, so a sample must be `response.create` with its
  own `instructions` and `tool_choice: "none"`.
- **`response.done` is not "she stopped talking."** Count scheduled buffers.
- **`startAudio()` returns early while `playFormat` is set** — anything
  stopping the engine must clear it, or she is connected and deaf.
- **`Path.home()` under the lain service is `/var/lib/lain`.** Her keys and
  `persona.json` live there, owned by `lain`.
- Deploying lain is both remotes, then one `sudo` per unit. See `lain/CLAUDE.md`.
