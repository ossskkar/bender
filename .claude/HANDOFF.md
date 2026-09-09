# HANDOFF — Arisu on OpenAI Realtime, working (2026-08-31)

*Arisu's own snapshot. The lain-side routes are `lain/docs/arisu-brain.md`;
lain's state is `lain/.claude/HANDOFF.md` — the one handoff for that repo.*

## State

**Speech-to-speech works on the phone.** She hears him, answers, calls tools.
Verified from `/tmp/arisu-face.log`: steady tap (~31 buffers/3s), 8 speech
events for 7 turns, transcripts that answer *his* words.

**OpenAI account is live.** Google login, $10 loaded, auto-recharge OFF, key
`arisu` (Default project) at `~/.arisu-openai-key` (mode 600). Her Anthropic
key at `~/.arisu-key` is a DIFFERENT file — do not overwrite it.

**Server side (in `lain/`, deployed — note lain now runs on architect, not
the Mac; `lain/deploy.sh` is dead, see `lain/CLAUDE.md`):**
- `lain/server/realtime.py` — mints `/v1/realtime/client_secrets` with persona,
  speech rules, semantic VAD, PCM 24k both ways, voice `marin`, 37 tools.
- `GET /arisu/realtime?model=<m>` — returns `{value, expires_at, model, url}`.
  Allowlist `("gpt-realtime-2.1-mini", "gpt-realtime-2.1")`; anything else
  falls back to mini rather than spending. In `UNSAFE_GET` (CSRF-guarded).
- `POST /arisu/tool` — `{name, args}` → MCP bridge on the desk. Verified.

**Phone (`arisu/native/Arisu/`, builds clean, on the device — but the
*installed* build still points at the Mac and needs rebuilding against
architect):**
- `Live.swift` — WebSocket, mic→24k PCM, playback, tool relay, idle-close 90s.
- `Pet.swift` — three modes; `ContentView.swift` — capsule button bottom-right,
  cycles mini → full → whisper. Dot = connection state.
- Whisper path untouched and still reachable via the button.

**Broken/unfinished:** her persona. She answers as a chirpy assistant
("Say something and I'll beep it back"), not the sardonic pet. Debug logging
to `/arisu/debug` is still on and should come out.

## Barge-in — fixed, confirmed by Oscar 2026-09-09

**The main-actor hop was not the cause.** It was a real slowdown and it was
reverted (the loop re-arms on URLSession's callback thread again, via a
`nonisolated arm(_:)`, with the `stopped` check kept as an
`OSAllocatedUnfairLock` copy the callback thread can read). But it did not fix
interruption, and the face log on architect said why.

**`response.done` means the server stopped sending, not that she stopped
talking.** At 16:22:48 the log shows `response.output_audio.done` and
`response.done`; the interruption came at 16:22:50, still two seconds into
audio the player had already scheduled. Both events cleared `speaking`, and
`flush()` was gated on `speaking` — so interrupting late in any answer threw
nothing away. She talked over him to the end and then answered the sentence he
had said underneath her, which is exactly what he reported.

**Fix:** `input_audio_buffer.speech_started` flushes unconditionally, and
`speaking` now counts buffers that have actually left the speaker
(`scheduleBuffer(_:completionCallbackType: .dataPlayedBack)`) rather than
frames off the socket. Every `player.stop()` resets that count. The idle watch
gets a truthful `speaking` out of it too.

Installed on the iPad and **confirmed working by him.**

Note: server-side `interrupt_response` is still off (`LAIN_ARISU_INTERRUPT`
defaults to 0). The flush is local, and it is enough.

## Her mind is Hermes now (2026-09-09)

The realtime session is minted with two tools, not 37: `set_mood` and
`ask_hermes`. Everything that is not banter goes to Hermes on architect
through `lain/server/hermes.py`. The 36 lain MCP tools are gone from her
session — Hermes reaches the same data through his own mount, plus his memory,
skills and board. Her tool budget in `Brain.swift` is 120s because a Hermes
turn measured 9–18s today.

## Decisions & open questions

- **mini is the default.** $10/$20 per million audio tokens vs $32/$64 for
  `gpt-realtime-2.1` — 3.2x. Model is chosen by the desk at mint time, so
  switching needs no rebuild.
- No JSON contract in speech: mood/action arrive as a `set_mood` tool call,
  which is the 37th tool.
- Open: does `full` actually hold the persona better than `mini`? Untested —
  that is what the button is for.
- Open: OpenAI docs mention an `mcp` tool type for realtime sessions. Could
  point the session straight at the MCP server and delete the phone relay.

## Next steps

1. **Fix barge-in.** See the regression section above — restore the immediate
   re-arm in `Live.listen()` without giving up the `stopped` guard, then confirm
   on the phone that she can be cut off mid-sentence *and* still goes silent
   when paused. Both, in one build; they are the same code path.
2. Rebuild the app against architect — the installed one still calls the dead
   Mac address.
3. Tighten the persona for speech. `SPEECH_RULES` + `PERSONA` in
   `lain/server/realtime.py`; deploy lain (the `deploy-lain` skill), no app
   rebuild needed.
4. A/B mini against full with the button, same three questions each.
5. Test a delete by voice — the confirm-first guard has never met real audio.
6. Strip the `brain.debug` calls from `Live.swift` once it is stable.
7. Nothing is committed. `arisu/native/`, `arisu/.claude/`, `arisu/deploy.sh`
   and `lain/server/realtime.py` are all untracked.

## Gotchas

- **Enabling voice processing stops the engine.** `setVoiceProcessingEnabled`
  rebuilds the I/O unit, which invalidates every connection and stops the
  engine *after* `start()` has returned without throwing. Cost four builds.
  The fix is the `.AVAudioEngineConfigurationChange` observer calling
  `rebuild()` — do not remove it.
- **Session-level AEC is not enough** once playback goes through the same
  `AVAudioEngine`. Without VP on the input node she hears herself and loops:
  23 transcriptions in two minutes, none of them Oscar.
- Connect the player at the **hardware** rate, not 24k.
- The GA schema nests audio under `session.audio.input/output`. The flat
  `input_audio_format`/`voice` names in older examples 400.
- Docs: append `.md` to any developers.openai.com URL for the full reference.
  `platform.openai.com/docs/...` 403s; it redirects to `developers.openai.com`.
- The phone has no console. `/arisu/debug` → `/tmp/arisu-face.log` is the only
  way to see what it is doing. Clear it before each test run.
- `xcodebuild` must run from `arisu/native/`; the shell cwd resets between calls.

## Resume

"Read arisu/.claude/HANDOFF.md and continue — realtime works, her personality
is wrong. Tighten the persona in lain/server/realtime.py and A/B mini vs full."
