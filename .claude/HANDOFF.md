# HANDOFF — Arisu (2026-09-23, evening)

*Progress lives in the lain Backlog. This session's work is the journey
"I see Arisu's own portrait blink and speak". Earlier threads (the VRM, the
character shopping) are unchanged and their record is in the Backlog too —
the shopping hunt is still open and his last word was **no** to the nit02
cyber model.*

## State — what works now

A third face track, **animating the flat portrait itself**. Nothing is
redrawn: every frame is a LivePortrait warp of `faces/portraits/arisu.png`.

- `flatface/make_sprites.py` — renders the sprites offline on CPU. Mouth
  ladder (5 levels), gaze (4), smile, smile_big, curious, concerned,
  mouth_wide, mouth_round. ~1 min per sprite, ~25 min for the set. Each pose
  is stored with the box where it differs from neutral, so the mouth swaps
  without touching the eyes.
- `flatface/make_poc.py` — composites them at 25fps and drives the mouth from
  a wav's loudness envelope. Blinks are geometric (see Gotchas).
- `flatface/arisu_poc.mp4` — the 10s proof clip, **sent to him, not yet
  judged**. Idle, blinks, gaze shifts, a raised-brow beat, speech (macOS
  `say`), back to idle.
- `flatface/test_flatface.py` — 4 asserts, all passing.
- LivePortrait lives at `~/tools/LivePortrait` (outside the repos): its own
  venv, torch 2.2.2 CPU (the last build with Intel-Mac wheels), 2GB weights.

## Decisions & open questions

- **Blinks are not LivePortrait.** Its eye retargeting cannot close an anime
  eye — it smears the iris into a rainbow. `sprites/blink_shut.png` is the
  evidence, kept on purpose. Gaze, mouth and brows through LivePortrait are
  good.
- **Mouth openness capped at 0.38.** Above that the interior goes to grey
  photographic mush. The knob is the one list in `poses()`.
- **Open:** does the mouth need an ink/posterize pass? That is his eye to
  judge from the clip, not something to decide for him.
- **Not built on purpose:** the lain face page and expression-per-reply. He
  said explicitly not to build the integration until the proof is judged.

## Next steps

1. Get his verdict on `flatface/arisu_poc.mp4`.
2. If the mouth reads as too mushy: try a posterize/ink pass on the mouth box
   in `make_poc.py` before touching the ladder.
3. Only after the verdict: serve it as a face page in `lain/arisu/`, loading
   `live2d/arisu-lipsync.js` for the amplitude — the contract is already the
   same 0..1 number.

## Gotchas

- Render with `--flag_force_cpu` **and** `flag_use_half_precision=False`;
  CPU torch has no fp16 layer_norm and dies with "LayerNormKernelImpl".
- `requests` is missing from `requirements_base.txt` once gradio is skipped.
- 532x535 is an odd height; ffmpeg needs a pad filter for yuv420p.
- Pose boxes must use a threshold relative to that pose's own peak change:
  two renders of the same face differ slightly everywhere (mean 0.67), so a
  fixed threshold returns the whole portrait.

## Resume

Read this file, then ask him what he thought of `flatface/arisu_poc.mp4`.

    cd /Users/oscar/Documents/claude-projects/arisu/flatface
    python3 make_poc.py --audio sample-voice.wav --out arisu_poc.mp4
