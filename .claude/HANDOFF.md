# HANDOFF — Arisu web + 3D model (2026-09-23, away session)

*Progress lives in the lain Backlog (Arisu → "Arisu appears as a 3D model…" and
"I use Arisu on the web like on the iPad"). Earlier detail is in git history.*

## State

- **Web page matches the iPad** (lain df5a49d, bf5d2d4): tap shows chrome,
  double tap talks, red mute, voice commands, no meter. Oscar confirmed on the 16 Pro.
- **Her default is V26** (`lain/arisu/vrm/arisu.vrm`). Rule (Oscar, 09-23): the
  latest version is always the default. Every version stays a face of its
  own (V5, V11–V26) on the web and in `FaceView.arisu3D` (iPad, compiles,
  needs his weekly build). All pass `tests/check_arisu_loading.mjs` (12 clips).
- **Arisu's saved face is now `Arisu3D`** (was "Arisu3D V20", his own pick) so
  she follows the latest. Backup: `arisu/v1-build/backups/characters-2026-09-23.json`.
- **Build chain:** `sh v1-build/tools/build.sh <out.vrm>` = `make_white_suit.py`
  (paint) → `reshape.py` (proportions, apply-pose-as-rest) → `long_hair.py`;
  then `python3 tools/publish_version.py N stem render.png`. Source is Codex's
  V11; `lain/arisu/vrm/MODEL.md` lists what each version changed.

## Decisions & open questions

- Codex (09-19/20) made V5–V11, then suggested buying BOOTH "Peke". Not bought.
- Everything edits the VRM directly (numpy), not Blender: reversible, keeps rig,
  expressions and clips. Blender 4.5 + VRM add-on are installed if needed.
- Graphite renders navy on the page: that is the idle state light, not the model.
- His Chrome cannot make a WebGL context (acceleration off); check in Safari.

## Next steps

1. Oscar looks at her in Safari on the 16 Pro and says what still differs.
2. Candidates: side-parted bangs (sheet) vs centre part; white hip plates with
   red marks; idle arms closer to the body (clip-level, affects every version);
   stepped edges where big triangles meet the graphite panels.
3. Still open: 60 fps on the 2020 iPad Pro; her mouth in a real Safari call.

## Gotchas

- Render: `python3 -m http.server 18796 --bind 127.0.0.1` in `lain/`, then a CDP
  script (see `tests/check_arisu_loading.mjs`). `--headless=new --screenshot` hangs.
- Body clips only start for files named `arisu*` — name probes `arisu_zz_probe`.
- Rotating `__vrm.scene` flings the hair; wait 5 s before judging it.
- Positions in `make_white_suit.py` are V11 bind-pose metres (before reshape).
- lain has unrelated uncommitted work (lights, systems.html); commit only yours.

## Resume

"Read arisu/.claude/HANDOFF.md and continue with what Oscar said about V26."
