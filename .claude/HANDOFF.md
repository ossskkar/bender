# HANDOFF — Arisu (2026-09-17 afternoon, 3D model loop with ChatGPT)

*Progress lives in the lain Backlog (Arisu → "Arisu appears as a 3D model on the iPad and the web").*

## State

- **Claude drives the ChatGPT conversation directly** (Oscar's go-ahead, 2026-09-17: "you do the conversation, I won't intervene"). Chrome tab, chat titled **"ChatGPT Plus Features"** = https://chatgpt.com/c/6aaad90a-89e0-83eb-8321-7758f0b8e439 (NOT "3D Avatar Creation").
- Loop per round: download ChatGPT's `arisu_vX_Y_*.py` + `MESSAGE_FOR_CLAUDE_*.txt` (file card → viewer → Download button in its banner; Escape) → **read the script** → run it headless on `v1-build/arisu_v1_blockout.blend` → render + measure → write `v1-build/arisu_vX_Y_note_for_chatgpt.txt` → upload note + renders (file input, max ~10 MB per call, files must be under the project) → short summary message → wait ~100 s → next.
- **Last sent: V2.25f PASS + armour inventory; asked for V2.26 (armour rigging).** Head phase: V2.24 read-only diagnostic; headset V2.25 -> V2.25f (6 rounds). Accepted design: angular temple module bone-parented to J_Bip_C_Head, hair "micro-channel" (345 Hair verts pulled in, 186 head-only core + 159 blended weights, no mask), own white material. Saved as NEW file `v1-build/arisu_v2_25f.blend`. **Next rounds run on arisu_v2_25f.blend**, not arisu_v1_blockout.blend (that stays the V2.23c body baseline; pre-V2.23c backup `arisu_v1_blockout_pre_v223c.blend`).
- Confirmed V3 blocker: 75 ARISU armour meshes have no parent/weights and export as root nodes (won't move with the skeleton). Inventory with suggested bones: `v1-build/arisu_v2_26_armour_inventory_for_chatgpt.txt` + `arisu_v2_25f_armour_inventory.json`. V2.26 = armour rigging.
- ChatGPT's roadmap after that: face expressions -> V3 rigging/motion clips -> V4 optimise + VRM 1.0 export + app QA.
- Frozen/passed: arms (V2.4 + Body Tops_01 mask), full torso (V2.15: dense chest, inset/emblem, slim wings, conforming pelvis), boots (V2.23c), legs hip->ankle (V2.21: bone-line x +/-0.074, conforming thigh/knee/shin shells, cores hidden, knee joint 30 mm, hip connector seated). Known cosmetic: small dark notch at each kneecap outer edge (deferred by ChatGPT).
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
- ChatGPT's recurring slips: global bounds as local anchors, flat boxes behind curved shells, footprints outside shells, materials by guessed names. Check these before running.
- MESSAGE_FOR_CLAUDE files sometimes don't download; the reply text has the render list.
- Source VRM: `~/Downloads/arisu_v0.3.vrm`. Round scripts land in `~/Downloads`.
- For surface details, measure underside-to-surface by casting down onto the base, then up onto the detail's evaluated mesh, with samples at 2%/98% of the footprint (20% insets hid end float).
- Temporary VRM export test: `bpy.ops.export_scene.vrm(filepath=<scratch>, ignore_warning=True, armature_object_name='Armature')`, then parse the GLB JSON (springs, node parents, POSITION/JOINTS/WEIGHTS). The exporter applies modifiers and takes Principled Base Color as baseColorFactor.
- Renders use one top-front SUN: faces pointing +/-X render dark (not a material bug).
- ChatGPT's download links sometimes open a code viewer: click the link text, then the download icon at top right (913,25), then Escape.
- Tools: `v1-build/tools/run_round_legs.py` and `run_round_torso.py` (replace SCRIPT/TAG; the legs one has the core-vs-shell, rear-protrusion and hip checks), `render_views.py`, `import_and_render.py`, `webkit_shot.swift`.

## Resume

"Read arisu/.claude/HANDOFF.md, open the ChatGPT chat and continue the 3D loop from V2.26 (armour rigging, runs on arisu_v2_25f.blend)."
