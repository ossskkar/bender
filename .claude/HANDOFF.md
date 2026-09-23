# HANDOFF — Arisu web + 3D model (2026-09-23)

*Progress lives in the lain Backlog (Arisu → "Arisu appears as a 3D model…" and
"I use Arisu on the web like on the iPad"). Earlier session detail is in git
history of this file.*

## State

- **Web page matches the iPad** (lain df5a49d, bf5d2d4, live): one tap shows
  legend + buttons, next hides; double tap starts/ends the call; red mute;
  voice commands (show/hide subtitles, open/close settings, mute). No "•••"
  button, no meter bars (Oscar: not needed). Oscar confirmed the tap on the 16 Pro.
- **3D versions are separate faces** in Settings > Face: Arisu3D (= arisu.vrm = the latest,
  now V20; Oscar: latest is always the default), V5, V11–V20. All live on architect
  (SHA-256 checked), all pass `tests/check_arisu_loading.mjs` with 12 clips.
  The iPad's `FaceView.arisu3D` lists the same (compiles; needs his weekly build).
- **V12–V16 (Claude)** built from V11 by `v1-build/tools/make_white_suit.py`,
  editing the VRM directly (no Blender): white suit, soft seams, graphite
  gloves/sides/V panel, box armour gone, white arms, over-ear headset, white
  shoes, sheet hair colour; V17 headband + slim smooth arms; V18 round
  graphite knees; V19 neutral outline, glowing cyan; V20 smaller shoulder
  joints, clean waist, soft band edges. Target: the Type-02 sheet,
  `~/Downloads/ChatGPT Image Sep 16, 2026, 10_44_38 PM.png`.
- Fixed: body clips only started for `arisu`/`arisu_v5` stems (V11 had none).

## Decisions & open questions

- Codex (09-19/20) made V5–V11 and conceded the model missed the bar; it
  suggested buying BOOTH "Peke". Not bought. Claude continued on the own model.
- Oscar 09-23: the latest version is always the default. Each new version is
  also copied over `lain/arisu/vrm/arisu.vrm` and `thumbs/Arisu3D.png`.
- Assumption: the red outline, navy graphite and stepped band edges are the
  renderer and triangle masks, not his taste; V19 fixes the outline only.

## Next steps

1. Blender pass (headless bpy, Blender is installed): proportions, hair.
2. Copy that file over `lain/arisu/vrm/arisu.vrm`, bump `v=` in
   `native/Arisu/FaceView.swift`, deploy (deploy-lain skill).
   Adding a version touches three lists: `ARISU_3D` (web), `FaceView.arisu3D`
   (iPad), and a thumb.
3. V21+ needs Blender: body proportions and hair shape against the sheet;
   texture passes have reached what they can do.
4. Still open: 60 fps on the 2020 iPad Pro; her mouth in a real Safari call.

## Gotchas

- Render check: serve `lain/` with `python3 -m http.server 18796 --bind 127.0.0.1`,
  then a CDP script like `tests/check_arisu_loading.mjs`; `vrm/index.html?file=<stem>`.
  `--headless=new --screenshot` hangs on the render loop; use CDP.
- UV probe trick: swap the suit texture for a UV gradient, render, read the colour.
- Adding a version: VRM into `lain/arisu/vrm/`, a line in `ARISU_3D`
  (`arisu/index.html`), a 300×400 thumb `live2d/thumbs/<name>.png`.
- lain has unrelated uncommitted work (lights, systems.html); commit only your files.

## Resume

"Read arisu/.claude/HANDOFF.md and continue with the 3D version Oscar picked."
