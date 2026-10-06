# Native voice follow-up, 2026-10-04

Source of truth: Arisu Backlog journey j3p1oc2c5oo in Lain. This is a prepared
candidate on codex/away-native-voice, based on 4eca8e4, not an installed release.
Worktree: /private/tmp/arisu-away-native. Concurrent main UI/chat edits and
untracked assets were preserved; merge current main before a release build.

Changes: native solo plans use committed audio item IDs; PTT waits for that
acknowledgement. think/ask_hermes sends the exact completed caption, with a
bounded two-second wait and no inferred fallback. Failed/empty/unbound/stale/
cancelled input cannot dispatch. Old connection callbacks/completions cannot
mutate a replacement connection; dispatched tool work still finishes remotely.
Current captions reach the UI once, after commit; stale captions cannot trigger
local UI commands. Whole explicit silence commands replace quiet-substring matching. Returned
source links go directly to the transcript without a fake spoken log; final
speech is grounded in confirmed answers, with URLs replaced by a transcript
reference. Group room input keeps its existing tool contract. Caption, response,
link-display and answer state is bounded. Added response status and queued-audio
flush diagnostics to help distinguish provider termination from local playback
interruption; these diagnostics do not establish the cause of past cutoffs.

Checks:
- python3 native/checks/voice-controls.py
- python3 native/checks/voice-input.py
- xcrun swiftc -frontend -parse native/Arisu/*.swift

The compiled Foundation fixture executes production runTool, workDone,
speakReply, rememberAnswer and VoiceInputs with synthetic network/audio sinks.
It covers exact captions, ordering, failure/empty/timeout, duplicate commits,
reset, cancellation, stale input, dispatched work, explicit quiet, group input,
bounds and a complex source URL with grounded qualified facts. It is not an
AVAudioEngine/WebSocket event-loop or physical microphone test.

Full Xcode iOS build was attempted and failed at CompileAssetCatalogVariant:
CoreSimulatorService unavailable / no available simulator runtimes. Whole-app
iOS typecheck was attempted but Observation macro's plugin cannot start its
sandbox in this session. No sandbox workaround, signed build, device install,
measured microphone accuracy or latency improvement is claimed.

Next: merge current app changes, complete a normal signed build when Xcode's
services are available, install on an unlocked iPad/iPhone, test real captions,
source links, PTT/follow-ups/interruptions and inspect the new completion/flush
logs. Native response-create serialization remains a separate unresolved risk;
this candidate preserves the existing scheduler rather than replacing it.
