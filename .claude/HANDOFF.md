# HANDOFF — Arisu (2026-09-24)

*Progress lives in the lain Backlog, journey "I see Arisu's own portrait blink
and speak". The VRM and character-shopping threads are untouched and recorded
there too; the shopping hunt is still open.*

## State — what works

A third face track: **animate a flat portrait as it is**. Every frame is a
LivePortrait warp of the original image, so the artwork is preserved. Nothing
neural runs at display time.

- `flatface/make_sprites.py` — renders the sprite set offline on CPU: mouth
  ladder (5), gaze (4), smile, smile_big, curious, concerned, mouth_wide,
  mouth_round, blink_half, blink_shut. ~1 min a sprite, ~25 min a set.
  `--only` adds to an existing set instead of wiping it.
- `flatface/make_poc.py` — composites at 25fps, mouth driven by the wav's
  loudness (the same signal `arisu-lipsync.js` gives from her voice).
  `--style hologram` puts the `faces/renderer.js` signal-face look on top.
- `flatface/test_flatface.py` — 4 asserts, passing.
- **Five portraits sampled**, clips in `flatface/`: `arisu_poc.mp4` (Yamato),
  `arisu_neon_poc.mp4`, `arisu_ayame_poc.mp4`, `arisu_wired_poc.mp4`,
  `arisu_ghost_poc.mp4`. Ayame is the best of them.
- LivePortrait lives at `~/tools/LivePortrait`: own venv, CPU torch 2.2.2,
  2GB weights.

## Decisions & open questions

- **Blinking is per-portrait.** Four of five close their lids through
  LivePortrait. Only the Yamato art cannot — its very large flat iris makes
  the eye retargeting smear a rainbow — and there `make_poc.py` squashes the
  lids geometrically instead. Render `blink_shut` and look; it takes a minute.
- **Eye positions are measured, not detected.** `faces/<id>.json` carries
  eyeL/eyeR plus `eyeBox`. Three attempts at deriving them automatically were
  thrown away (a gaze diff finds the iris, not the eye; a shut-eye probe
  smears over the cheek).
- **Sprite sets are gitignored** — 36MB each at 1024x1536. Regenerate them.
- **Open, his call:** which portrait Arisu is built from, and whether to
  restyle (e-ink/pixel) rather than keep the painting. Restyling does not
  reduce the work but hides the mouth mush, iris smear and box seams.
  `faces/renderer.js` already has both an e-ink mode and the hologram raster.
- **Not built on purpose:** the lain face page and expression-per-reply. He
  asked for proofs first.

## Next steps

1. **One portrait never reached the disk** — the white/lilac-haired horned
   android he asked for twice. Ask him to save it into `~/Downloads`, then:
   `cd ~/tools/LivePortrait && .venv/bin/python <flatface>/make_sprites.py
   --source <img> --out <flatface>/sprites-<name>`, measure her eyes into
   `faces/<name>.json`, then `make_poc.py`.
2. `arisu_ghost_hologram.mp4` was still rendering when this was written; it is
   a detached process and should be on disk. Send it to him.
3. Get his pick of portrait and style, then build the face page in
   `lain/arisu/`, loading `live2d/arisu-lipsync.js`.

## Gotchas

- Render with `--flag_force_cpu` and `flag_use_half_precision=False`; CPU
  torch has no fp16 layer_norm.
- Odd image heights need ffmpeg's pad filter for yuv420p.
- Pose boxes use a threshold relative to that pose's own peak: two renders of
  the same face differ slightly everywhere.
- The hologram filter needs a flat-fill term of 0.60, not the renderer's 0.20
  — at 0.20 a cel-shaded face is almost invisible.

## Resume

Read this file, then ask Oscar which portrait and which style Arisu gets.

    cd /Users/oscar/Documents/claude-projects/arisu/flatface
    python3 make_poc.py --sprites sprites-ayame \
      --face-json ../faces/arisu-ayame.json --audio sample-voice.wav --out x.mp4
