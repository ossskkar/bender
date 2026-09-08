# Arisu, native

The web face is kept; this replaces it on the phone. **The brain is untouched** --
same `/arisu/listen`, same JSON, so the planner, board, habits, diary and the
rest of the 36 tools work here from the first run.

## Why native

Every remaining problem was a Safari problem:

| Problem in the browser | Here |
|---|---|
| Mic handed over at ~-43 dBFS, whisper dropped her name | `AVAudioEngine`, plus explicit normalisation in `Ear.normalise` |
| `speechSynthesis` silently refused to speak; reply audio came from the Mac at 3-6s | `AVSpeechSynthesizer`, resident, ~0.2s |
| She heard herself; `onend` never fired | `.voiceChat` echo cancellation + a real `didFinish` |
| `ScriptProcessorNode` ran the sample loop on the main thread | tap runs on its own thread |
| A full-screen `drop-shadow` re-blurred every frame | a cached `.shadow` |

## Files

| File | What it is |
|---|---|
| `Ear.swift` | mic, noise-floor gate, pre-roll, gain normalisation, 16k WAV |
| `Brain.swift` | `POST /arisu/listen` over Tailscale, decodes `Snap` |
| `Voice.swift` | `AVSpeechSynthesizer`, raises/lowers the ear's `deaf` flag |
| `Pet.swift` | joins the three together; the only thing the view watches |
| `ContentView.swift` | the hologram, caption, meter |
| `ArisuApp.swift` | entry point; keeps the screen awake |

## Project settings that are not in the source

Xcode owns these, so they have to be set once in the target:

- **Info.plist** -- `NSMicrophoneUsageDescription` ("Arisu listens for her name.")
- **Signing & Capabilities** -> **Background Modes** -> tick **Audio, AirPlay, and
  Picture in Picture**, or she goes deaf the moment the screen locks.
- **Assets** -- add `lain-face`, `lain-face-cy`, `lain-face-mg` from
  `arisu/assets/` as image sets with those exact names.
- Deployment target: iOS 17 or later (`@Observable`-era SwiftUI is not used, but
  `persistentSystemOverlays` needs 16.4+).

## Gotchas

- Free provisioning means the build expires after **7 days** -- re-run from Xcode
  with the phone plugged in to renew. Oscar accepted this rather than pay $99/yr.
- The Tailscale hostname is hardcoded in `Brain.base`. If the tailnet name ever
  changes, that is the one line to edit.
- `Ear.gate` is `max(0.006, floor * 2.6)`. The browser needed 0.002 because its
  input was so quiet; native input is much hotter, so do not copy that number
  back across without measuring.
