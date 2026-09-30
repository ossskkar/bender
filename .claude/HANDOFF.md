# Handoff — Record works end to end, app-wide restyle (2026-10-01)

State and progress: Backlog project **Arisu**. Journey "I record a brain dump
on the iPad…" has every step ticked and sits in **review**, waiting for
Oscar's word to move it to done.

## State
- **Record works**: iPad records → lain `POST /dumps` → whisper on architect →
  history; insights (Gemini via `llm.ask`) confirmed good by Oscar.
- **whisper-server now runs on architect**: user unit `whisper.service`
  (linger on), binary `~/whisper.cpp/build/bin/whisper-server`, model
  `~/.cache/whisper-models/ggml-base.en-q5_1.bin`, 127.0.0.1:20301 — the
  address lain already calls. It was only ever on the Mac before; the first
  retry read as silence and the iPad deleted that recording.
- lain `7c4b341`: a dead ear is a 503, not a 422, so the iPad keeps the WAV.
  Live (lain restarted after the pull).
- iPad app (arisu `7f87c48`, installed): the Record panel's look everywhere.
  `Grid`, `Brackets`, `.console()` live in `Skin.swift`; `Skin.radius` is 0;
  `Raised` glows when its edge is lit; `.fontDesign(.monospaced)` at the root
  and on each sheet. Voice mode: the meter is gone, its place shows
  `> LISTENING_` etc. in the state colour.
- Rough edge: in voice mode the face's own dark square hides the grid.

## Decisions
- Mid-session `git stash/pull/pop` on architect's `~/lain` is safe with a
  backup patch first (`~/lain-uncommitted-2026-09-30.patch`, delete when the
  chat-import work is committed — it appears to be: HEAD is now `e3d59d4`).

## Next steps
1. Oscar says done → `backlog_journey_status` Arisu / brain dump → done,
   `confirmed_by="oscar"`.
2. If the chat-import work is committed, remove the backup:
   `ssh architect 'rm ~/lain-uncommitted-2026-09-30.patch'`.
3. New journey in backlog: command buttons over the voice animation
   (Today's Brief first).
4. Deck in landscape on the real iPad still unchecked.
5. Pencil scribble idea: see its Backlog journey.

## Gotchas
- The auto-mode classifier refuses `sudo systemctl restart` over ssh; Oscar
  runs it with `ssh -t architect 'sudo systemctl restart lain.service'`.
- iPad installs over Wi-Fi (`iPad.coredevice.local`); no cable needed. The
  Dell hub cannot charge a flat iPad Pro ("Not Charging").
- New Swift files must be added to `project.pbxproj` by hand.
- Stop simulators after screenshots (`simctl terminate`, `simctl shutdown`).

## Resume
"Read arisu/.claude/HANDOFF.md and continue with the next step."
