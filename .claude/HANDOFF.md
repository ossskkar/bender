# HANDOFF — Arisu 3D model (2026-09-18, ~03:30)

*Progress lives in the lain Backlog (Arisu → "Arisu appears as a 3D model on the iPad and the web").*

## State

- **Her model is live.** lain 62cb2ad swapped `lain/arisu/vrm/arisu.vrm` from the pixiv stand-in to
  Arisu V4.0; architect serves it (14,523,564 bytes). https://architect-server.tailaa64e9.ts.net:8443/arisu/?model=Arisu3D
  Not yet seen by Oscar on a real screen.
- **V3 is frozen, 12/12 clips:** `v1-build/arisu_v3_3c.blend` (verified on reopen: 12 actions, signatures
  match the QA run). VRMAs: `v1-build/vrma_v3_3c/` (12 files).
- **V4.0 done by Claude, no ChatGPT:** `v1-build/arisu_v4_0.blend`. Hair COLLAPSE-decimated 0.6 under the
  armature modifier (27,090 → 16,254 tris, 0 unweighted verts, looked identical at 0.5), thumbnail
  2048² → 512². Export: 47,144 tris, 13.85 MB, 86 meshes, 18 materials, 21 expressions, 8 springs.
- **Runtime check passed** (arisu tools/runtime_harness with lain's lib/): all 21 expressions drive their own
  morphs, stacking works, zero values give zero displacement.
- **Not done:** the lain page does not play the body clips — needs `@pixiv/three-vrm-animation`.

## Decisions (overturn cheaply)

- ChatGPT's hard distinctness metric (max per-bone angle) could not tell a shoulder raise from a drop — V3.3b
  and V3.3c scored an identical 9.46°. I put both options to ChatGPT; it accepted V3.3c on shoulder height
  (+14.5 mm vs nod ~0) and froze V3. I did not override its hard gate myself.
- Deployed the swap without asking: it was the approved next step, it is one `git revert` away, and a static
  file needed no service restart.
- Left the 4 `MToon Outline (…)` materials: they have 2 users each (VRM add-on refs), and export already drops
  them (18 materials in the .vrm).
- Did not use Codex; the web chat was used for 3 more messages.

## Gotchas

- lain's own page in headless WebKit shows only its first frame (rAF never runs off-screen): eyes shut, mouth
  open, head close-up — for the stand-in too. Test the model with `tools/runtime_harness` (calls
  `vrm.update` itself), and the page on a real screen.
- ChatGPT's "Download file" buttons do nothing: click the filename → Download in the viewer → Escape.
- Shoulder axes: Z raises (L +, R −); X is forward/back only. Bone frames are mirrored L/R.
- Budget math: the work iPhone pulled ~80 KB/s from the desk (2026-09-15), so 13.85 MB ≈ 3 min first load.

## Next steps

1. Oscar looks at https://architect-server.tailaa64e9.ts.net:8443/arisu/?model=Arisu3D in Safari; tick the Backlog step.
2. With his OK: vendor `@pixiv/three-vrm-animation` into `lain/arisu/vrm/lib/`, copy the 12 .vrma into lain,
   play idle/listening/talking/thinking/asleep by state and the reactions on events.
3. Optional, his call: a texturing round (flat panels are the gap to the reference pictures); texture `_11`
   (2.82 MB) halving would cut first-load time.

## Resume

"Read arisu/.claude/HANDOFF.md; Oscar has checked the 3D page — continue with step 2."
