# Handoff — Arisu iPad: Codex's work finished, Deck corrected (2026-10-07)

## State
All of Codex's pending Arisu work is on `main`, pushed to origin and
timemachine, and **installed on the iPad** (build of `864eb19`).
- `bdb9b6c` Codex's modes (base / free / singularity) + deck work, made to compile.
- `cc8dc2d` merged `codex/away-native-voice`: exact captions to think/ask_hermes,
  stale input can't dispatch, cutoff diagnostics.
- `f9856ae` rest of Codex's 10-04 patch: `Pet.toggleMicrophone` (mic starts an
  unmuted call after Safari ended one), free-mode tap shows commands/transcript.
- `370f564` + `864eb19` Oscar's corrections: DeckRail.swift back to `5c934b9`
  (usage-ranked keys, vertical page wheel, agents band); a row of four
  **inside the Deck, above the app groups**: Close (Cmd-Q on Mac), Screenshot,
  Light, Sleep. Light = God's Eye strip via lain `POST /lights {on}`.
- **Confirmed by Oscar on the iPad:** Light toggles God's Eye; old deck is right;
  row position (said "cool").
- **Unproven:** Close, Screenshot, Sleep on device; a live voice call (captions,
  source links, PTT, interruptions, mic after Safari); free-mode voice fade.
- Mac deck agent `com.oscar.arisu-deck` restarted on the new `deck.py`
  (has `/deck/sleep`, Citrix group). Selftest passes.
- Canvas (desk screen, previous handoff) unchanged: built, switched off, Mac
  slowness undiagnosed — `ponytail:` on `Backdrop` in `canvas/main.swift`.

## Decisions & open questions
- Light means God's Eye, never Singularity (Oscar). Singularity is reached by
  three-finger swipe / Settings mode picker.
- The deck stays usage-ranked; do not reintroduce horizontal paging (Oscar).
- Kept from Codex without objection so far: three modes, Sleep also sleeping the Mac.
- Open: one swipe once flipped the screen to Singularity; never reproduced.
- Open: `codex/away-native-voice` branch is merged but not deleted (permission
  check refused the delete). Harmless.

## Next steps
1. OSCAR: on the iPad try Close, Screenshot, Sleep, and one live call; report.
2. Tick `jei6q459bs0` step "Try the four Deck buttons" and `j3p1oc2c5oo` step
   "Build, install and validate native…" when he confirms.
3. Rebuild + reinstall after any change (iPad id `085B9100-31D5-5A2D-B44C-82D143A30ACA`):
   `xcodebuild -project native/Arisu.xcodeproj -scheme Arisu -destination 'generic/platform=iOS' -derivedDataPath <dd> -allowProvisioningUpdates build`
   then `xcrun devicectl device install app --device <id> <dd>/Build/Products/Debug-iphoneos/Arisu.app`
4. Then back to the Canvas slowness (previous handoff's step 1).

## Gotchas
- **The simulator drives the real Mac deck.** Any deck key tapped there fires on
  the Mac — a Close tap quit the Claude app. Screenshot only, never press keys.
- Cold simulator launch shows white/black for 30–60 s; it is not a crash.
- Codex's sandbox cannot build (no simulator runtimes); its "parse passes"
  claims hid a missing type and a duplicate function. Always build here.
- `xcodebuild -destination id=<iPad>` fails; use `generic/platform=iOS` + devicectl.
- Voice checks: `python3 native/checks/{voice-controls,voice-input,microphone}.py`;
  deck: `python3 deck/deck.py selftest`.
- Superseded, safe to bin: `~/Documents/arisu-native-handoff-2026-10-04/`,
  `~/Documents/arisu-new-session.md`.
- Stage paths, never `-a`: untracked `v1-build/*.vrm`, `flatface/sprites-*`, `.agents/` aren't this work.

## Resume
"Read arisu/.claude/HANDOFF.md; ask Oscar how Close, Sleep and a live call went on the iPad."
