# HANDOFF — Arisu 3D model (2026-09-17 evening)

*Progress lives in the lain Backlog (Arisu → "Arisu appears as a 3D model on the iPad and the web").*

## State

- **Claude drives the ChatGPT conversation directly** (Oscar: "you do the conversation, I won't intervene"). Chrome tab, chat **"ChatGPT Plus Features"** = https://chatgpt.com/c/6aaad90a-89e0-83eb-8321-7758f0b8e439 (not "3D Avatar Creation"). Oscar sometimes types in that chat himself — read the last messages before acting.
- **Round loop:** download ChatGPT's `arisu_vX_*.py` + `MESSAGE_FOR_CLAUDE_*.txt` → read the script for safety → run it **unchanged** headless on the current baseline → measure + render → write `v1-build/arisu_vX_note_for_chatgpt.txt` → upload note + sheets → short summary → next. Report script bugs, never silently patch them.
- **Baseline chain (each round saves a NEW file, never overwrites):** `arisu_v1_blockout.blend` (V2.23c body) → `arisu_v2_25f.blend` (head/headset) → `arisu_v2_26b.blend` (armour rigged) → `arisu_v2_27.blend` (articulation) → `arisu_v3_0d` → `arisu_v3_1e` → **`v1-build/arisu_v3_2b.blend` = current**.
- **Done and frozen:** body (arms V2.4, torso V2.15, legs V2.21, boots V2.23c), headset + hair channel (V2.25f), armour rigging (V2.26b: 67 rigid + 8 Body-weighted shells, 0 root nodes), articulation (V2.27), face/expressions (V2.28, validated in the real three-vrm runtime).
- **Animations (asset-side PASS), 8 clips in `v1-build/vrma_v3_2b/`:** idle, listening, wave, thinking, talking, nod, asleep, wake. One `.vrma` per clip.
- **Last sent:** V3.2b PASS report; asked ChatGPT for **V3.3 (reaction clips)** from `arisu_v3_2b.blend`.
- **Blocked:** runtime playback of the .vrma files needs `@pixiv/three-vrm-animation` downloaded (npm/CDN). Waiting on Oscar's approval; reported to ChatGPT every round as "RUNTIME VALIDATION: DEFERRED".
- Export snapshot: 57,980 tris, 86 meshes, 18 materials, 16.2 MB — over the 50k / 15 MB budget. Optimisation is V4.
- Current-model renders for Oscar/ChatGPT: `v1-build/arisu_current_model_full.png` and `_detail.png` (scratch `showcase.py`).

## Decisions

- Non-personal project material may go to ChatGPT (memory `data-rule-means-sensitive-data`). Renders/notes/.blend/.vrma stay local — repo `bender` is PUBLIC; only `v1-build/tools/` and this handoff are committed.
- Run ChatGPT's scripts unchanged; failed rounds are not saved.
- Blender 4.5.14 LTS (Intel Mac) + VRM add-on 4.7.1.

## Gotchas

- `vl.update()` before reading moved objects; some meshes have world-baked vertices; `material_index` is zero-based.
- Measure clearance by ray-cast, not vertex distance. Signed nearest-surface flips sign for parts that enclose the body (ElbowAxle reads −350 mm) — check renders too.
- Cycles modifier loops each F-curve over **its own** key range: every looping bone must be keyed at the first AND last frame.
- Blender AUTO handles are flat on the first/last key: without a Cycles modifier a loop stalls at the wrap.
- VRMA export = armature's active action + scene frame range; it writes constant tracks for every humanoid bone, so clips must key the base pose.
- Relaxed base pose: UpperArm Z −72.5 (L) / +72.5 (R), LowerArm X +15 both. Axis table: `v1-build/arisu_axis_table_for_chatgpt.txt`.
- Add-on preset names are snake_case (`blink_left`); glTF/runtime use camelCase.
- ChatGPT download links often open a code viewer: click the link text, then the download icon at (913,25), then Escape. Files land in `~/Downloads`.
- Chat upload: file input, ≤10 MB per call, files must be under the project. `.vrma` uploads are rejected.
- Renders use one top-front SUN; faces pointing ±X look dark (not a material bug).
- Tools: `v1-build/tools/` (run_round_*.py runners, render_views.py, `runtime_harness/` for the three-vrm WebKit tests). Scratch runners for the animation rounds: `v31c.py` (per-frame face-safety scan over all finger tails), `v32.py` (freeze + loop + transition + contact + VRMA audit).

## Next steps

1. Ask Oscar to approve downloading `@pixiv/three-vrm-animation`; then run the runtime playback test with `tools/runtime_harness/` (createVRMAnimationClip + AnimationMixer, face stacking, springs).
2. Continue the loop: V3.3 reaction clips on `arisu_v3_2b.blend`, using the `v32.py` check pattern.
3. After all clips: V4 — optimise to <50k tris / <15 MB, final VRM export, then put her in the app (`lain/arisu/vrm/`, model "Arisu3D", currently a pixiv stand-in).

## Resume

"Read arisu/.claude/HANDOFF.md, open the ChatGPT chat and continue the 3D loop from V3.3 (reaction clips, baseline arisu_v3_2b.blend)."
