# HANDOFF — Arisu (2026-09-25)

*Progress lives in the lain Backlog, journey "I see Arisu's own portrait blink
and speak". The VRM thread is untouched; character-shopping stays closed — he
chose to animate portraits he already has.*

## State — what works

**The flat portrait is her face in the app, live on architect.** Three sets,
switchable from Settings, **horn is now the default** (chosen 2026-09-25).

- `lain/arisu/flat.html` — the renderer. Base pose, mouth box swapped by the
  amplitude `arisu-lipsync.js` gives from her voice, eye boxes swapped for a
  blink, plus blinks (2.4–6 s) and glances (5–10 s) it runs itself. Exposes
  `setState`, `setAmplitude` and now **`setExpression`**.
- **Expression per reply shipped 2026-09-25.** `cues.js` gained
  `expressionFor(text)`: trouble beats a question beats delight beats plain
  warmth, anything unread stays neutral. `index.html` feeds it the
  `response.output_audio_transcript.delta` stream, so her face follows the line
  *while* she says it. The expression is worn only while `speaking` and dropped
  the moment she stops.
- `arisu/flatface/export_web.py` — 41 MB sprite set → ~1.8 MB of half-size
  JPEGs. Output goes to `lain/arisu/flat/<set>/`.
- Sets: **horn** (white/lilac horned android, default), **ayame** (pink 03
  SYNTH UNIT), **proto** (blue bob). Portraits in `arisu/faces/portraits/`,
  landmarks in `arisu/faces/arisu-<set>.json`.
- `arisu/vrmtest/index.html` — drop a `.vrm` on it, it reports spec, tris,
  visemes, blink, licence, fps. Kept because `lain/arisu/vrm/` holds thirty.

**The iPad app draws the portrait too, since 2026-09-25 (`d0e7c51`).** Two bugs
made it keep showing her 3D model whatever the desk said:
- `FaceView` had never heard of the painted portraits. They are carried as the
  model `flat:<set>`, and an unrecognised model fell through to the character's
  default Live2D one, so `flat:horn` drew Arisu3D. It loads `flat.html?set=`
  from the desk now — the same page the web client frames.
- **The cast was only fetched in `begin()`**, so a screen sitting idle had never
  asked who she is: the face on launch was a guess and stayed one until somebody
  started a conversation. `arrive()` asks now.
- Verified in the iPad simulator against the live desk (launch, no conversation,
  horned portrait on screen), then built and installed on the iPad itself.
- **The free build expires every 7 days**; `xcodebuild -destination 'id=<udid>'
  -allowProvisioningUpdates` then `xcrun devicectl device install app` renews it
  over the network — no cable. A freshly signed certificate has to be trusted on
  the device once, by hand, before it will launch.

## Decisions & open questions

- **A set is carried as the model `flat:<set>`.** `?face=flat&set=horn` works.
- **Expression is read from her words, not tagged by the brain.** Tagging would
  be more accurate but it is a prompt change every turn and a leaked tag would
  break "nothing internal gets spoken aloud". Revisit only if the word list
  feels wrong in use.
- **3D and buying art both ruled out** (2026-09-25). If 3D returns: VRoid Hub
  or VRoid Studio, not BOOTH (Unity packages, not VRM).
- **Open:** whether the expressions actually read right — Oscar had not spoken
  to her yet when this was written. That is the next thing to ask him.
- **Asked and not built:** head turn and hair movement, the hologram style for
  the phones, the ink/posterize pass on the open mouth.

## Next steps

1. Ask Oscar whether the expressions read right in a real conversation. If the
   word list misfires, widen the regexes in `lain/arisu/cues.js` — not a model.
2. Hologram style by device for the iPhones (Backlog step 9): swap the filter
   at runtime rather than baking a second set of sprites.
3. Head turn, if he wants it: render yaw sprites per set, and decide between a
   mouth ladder per angle or turning only while silent.

## Gotchas

- **The expression reads in the eyes and brows only while she is audibly
  speaking** — the mouth box is pasted over the base, so lipsync owns her
  mouth. It lands fully in the gaps between words.
- **Her mouth moves less on `horn`** — thin closed lips, the mouth box only
  darkens 156 → 150 across the ladder, against a full change on ayame. This is
  the default set, so it is the one he will see.
- Render with `--flag_force_cpu`; a set is ~7 min, `--only a,b` adds to a set.
- Eye landmarks are measured by hand per portrait. Three attempts at deriving
  them automatically were thrown away.
- Sprite sets are gitignored (~40 MB); the exported JPEGs are committed.
- Deploy with the `deploy-lain` skill — both remotes, or they drift.
- The browser pane throttles rAF when hidden; sample a canvas over a second.

## Resume

Read this file, then ask Oscar whether Arisu's expressions read right when he
talked to her.
