# HANDOFF — Arisu (2026-09-25)

*Progress lives in the lain Backlog, journey "I see Arisu's own portrait blink
and speak". The VRM thread is untouched; the character-shopping hunt is closed
for now — he chose to animate portraits he already has.*

## State — what works

**The flat portrait is her face in the app, live on architect.** Three sets,
switchable from Settings:

- `lain/arisu/flat.html` — the renderer. Base pose, mouth box swapped by the
  amplitude `arisu-lipsync.js` gives from her voice, eye boxes swapped for a
  blink, plus blinks (every 2.4–6 s) and glances (5–10 s) it runs itself.
  Exposes the same `window.avatar` the signal face does: `setState`,
  `setAmplitude`. Nothing else in `index.html` changed but the routing.
- `arisu/flatface/export_web.py` — 41 MB sprite set → ~1.8 MB of half-size
  JPEGs with the boxes scaled. Output goes to `lain/arisu/flat/<set>/`.
- Sets: **ayame** (pink 03 SYNTH UNIT), **proto** (blue bob, PROTO-05),
  **horn** (white/lilac horned android). Portraits in `arisu/faces/portraits/`,
  landmarks in `arisu/faces/arisu-<set>.json`.
- `arisu/vrmtest/index.html` — drop a `.vrm` on it and it reports spec, tris,
  materials, whether the visemes and blink the browser needs are in the file,
  licence and fps. Written while deciding against buying a 3D model; kept
  because `lain/arisu/vrm/` holds thirty.

## Decisions & open questions

- **A set is carried as the model `flat:<set>`.** That reuses the saved-choice
  plumbing, the character record and links; the prefix is all that names the
  renderer. `?face=flat&set=horn` still works.
- **3D was ruled out** (2026-09-25). BOOTH's VRChat avatars ship Unity
  packages, not VRM: "Peke" lists its VRM as experimental, "Visarie" has none.
  If it ever comes back: VRoid Hub, or VRoid Studio for free.
- **Buying art was ruled out too.** The recommendation stands if he changes his
  mind: a 立ち絵 with layered PSD and 表情差分, ¥500–1500 — layers beat
  LivePortrait warps and skip the render entirely.
- **Open:** which set is her default. Ayame is what a bare `?face=flat` gives.
- **Asked and not built:** head turn and hair movement (see the Backlog step),
  the hologram style for the phones, expression-per-reply.

## Next steps

1. Ask him which set is the default, then make it the fallback in
   `index.html` (`if (FACE === 'flat' && !SET) SET = 'ayame'`).
2. Head turn, if he wants it: render yaw sprites per set, and decide between a
   mouth ladder per angle or turning only while silent.

## Gotchas

- **Her mouth moves less on `horn`** — thin closed lips, so the lip warp is
  subtle. Measured: the mouth box only darkens 156 → 150 across the ladder,
  against a full lip-to-interior change on ayame.
- Render with `--flag_force_cpu`; a set is ~7 min, `--only a,b` adds to a set.
- Eye landmarks are measured by hand per portrait, in fractions of the frame.
  Three attempts at deriving them automatically were thrown away.
- Sprite sets are gitignored (~40 MB); the exported JPEGs are committed.
- The browser pane throttles `requestAnimationFrame` when it is hidden, so a
  canvas read taken twice in a row looks frozen. Sample over a second.

## Resume

Read this file, then ask Oscar which portrait is her default.
