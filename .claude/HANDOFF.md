# HANDOFF — Arisu (2026-09-17, 3D model loop with ChatGPT)

*Progress lives in the lain Backlog (Arisu → "Arisu appears as a 3D model on the iPad and the web").*

## State

- **Claude drives the ChatGPT conversation directly** (Oscar's go-ahead, 2026-09-17: "you do the conversation, I won't intervene"). Chrome tab, chat titled **"ChatGPT Plus Features"** = https://chatgpt.com/c/6aaad90a-89e0-83eb-8321-7758f0b8e439 (NOT "3D Avatar Creation").
- Loop per round: download ChatGPT's `arisu_vX_Y_*.py` + `MESSAGE_FOR_CLAUDE_*.txt` (file card → viewer → Download button in its banner; Escape) → **read the script** → run it headless on `v1-build/arisu_v1_blockout.blend` → render + measure → write `v1-build/arisu_vX_Y_note_for_chatgpt.txt` → upload note + renders (file input, max ~10 MB per call, files must be under the project) → short summary message → wait ~100 s → next.
- **Last sent: V2.14 report** (wings slimmed but seam 4.7 mm off; pelvis moved 20 mm forward, floats). Waiting for V2.15.
- Frozen/passed: arms (V2.4, Body Tops_01 mask), dense 9x9 ChestFront (V2.10), inset/emblem layering (V2.13).
- 3D face page is live in lain (`arisu/vrm/`, model "Arisu3D", `?dev` panel). Uses the pixiv stand-in `arisu.vrm`; ChatGPT's model is not in the app yet (15.8 MB, over budget).
- Earlier this session (all deployed/installed): iPad+web state colours/legend/meter toggle, chat bubbles, one-button controls, Live2D spotlight + glow sliders + model picker.

## Decisions

- Data rule clarified: non-personal project material may go to ChatGPT (memory `data-rule-means-sensitive-data`).
- Render/notes stay local (repo `bender` is PUBLIC); only `v1-build/tools/` is committed.
- Blender 4.5.14 LTS (Intel Mac; Blender 5 dropped Intel) + VRM add-on 4.7.1 installed. VRoid Studio installed but unused.

## Gotchas

- `vl.update()` before reading moved objects (stale matrix_world cost a wrong report once; told ChatGPT).
- Blender `material_index` is zero-based; say so explicitly to ChatGPT.
- Some objects have world-space baked vertices (ChestInset, ChestFront, Torso prisms): location is not position.
- Measure clearance by ray-casting (vertex-only checks miss face-centre poke-through).
- Source VRM: `~/Downloads/arisu_v0.3.vrm`. Round scripts land in `~/Downloads`.
- Tools: `v1-build/tools/run_round_torso.py` (replace SCRIPT/TAG), `render_views.py`, `import_and_render.py`, `webkit_shot.swift`.

## Resume

"Read arisu/.claude/HANDOFF.md, open the ChatGPT chat and continue the 3D loop from ChatGPT's V2.15 reply."
