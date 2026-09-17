# HANDOFF — Arisu (2026-09-17, iPad controls, voice commands, mute)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

All three changes are in `native/Arisu/` and installed on the iPad. iPhone app and web do not have them.

- **Tap to show controls (f5bde79), verified by Oscar.** Fold button removed. Legend and
  button column start hidden; a tap anywhere on the screen toggles `chromeShown`. The
  Settings sheet moved to `body` so hiding the buttons never closes it.
- **Voice commands (123b6ee), verified by Oscar.** `enum VoiceCommand` at the end of
  `ContentView.swift`, run from `.onChange(of: pet.heard)` → `obey()`. Phrases: show/hide
  transcript (subtitles, captions, chat), group/solo mode|conversation, mute, open/close
  settings. She still replies to the line. No voice unmute (a muted mic sends nothing).
- **Mute keeps her awake (1a92d3a), NOT yet heard by Oscar.**
  - `faceState` no longer returns `asleep` when muted (the asleep face held the jaw shut).
  - The 90 s idle close in `startIdleWatch` now waits while `awaiting`, `openPlans` or
    `toolsOut` are non-empty. A muted room never refreshes `lastVoice`, so a long think
    was being cut off and its answer lost.

Earlier, still open: plan-first turns and chat bubbles (see git log `eafc833` and before).
architect's lain checkout carries someone's UNCOMMITTED glow edits; deploys there need
stash / pull / stash pop.

## Decisions

- Voice commands match his transcript on the device, not a model tool: instant, no desk change.
- Explicit phrases only, so talking *about* the transcript does not flip it.

## Open questions

- Should muting stop the dormant session waking on room noise? Not asked; left as is.
- Should she skip her spoken reply to a voice command? Oscar has not said.

## Next steps

1. Oscar asks something slow, mutes, and confirms she stays awake and answers. Then tick the Backlog step.
2. Port tap-to-show and voice commands to the web page (`lain/arisu/index.html`) and the iPhone app if he wants them (Backlog step on the web journey).
3. From before: read `ssh architect tail -50 /var/lib/lain/arisu-voice.jsonl` for `timing`/`superseded`.

## Gotchas

- Build and install on the iPad (device id `085B9100-31D5-5A2D-B44C-82D143A30ACA`):
  `xcodebuild -project native/Arisu.xcodeproj -scheme Arisu -destination 'id=…' -derivedDataPath <scratch>/dd -allowProvisioningUpdates build`,
  then `xcrun devicectl device install app --device <id> <dd>/Build/Products/Debug-iphoneos/Arisu.app`,
  then `xcrun devicectl device process launch --terminate-existing --device <id> com.oscar.arisu`.
- `VoiceCommand` check: copy the enum plus asserts into a scratch `.swift`, `swiftc` it, run it.
- Backlog MCP tools return ~80k chars; POST ops to `/backlog` directly (project `pspsrzn75jy`).
- Never make `ossskkar/lain` public (Cubism Core).

## Cloned voice (2026-09-17, parked)
- Backlog Arisu journey "Arisu speaks in a cloned voice": OpenAI realtime has no custom voices;
  needs text-out + local cloning TTS. architect (i5-8365U) and Mac (i9-9880H) have no GPU, too slow.
  ElevenLabs breaks the data rule. Waiting on a GPU.

## Resume

"Read arisu/.claude/HANDOFF.md, then check whether muting kept Arisu awake and answering."
