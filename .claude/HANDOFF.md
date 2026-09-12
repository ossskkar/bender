# HANDOFF — Arisu (2026-09-12)

*lain's own state is `lain/.claude/HANDOFF.md`; the homelab handoff owns the
Hermes side. **Every measurement and every reason is in `LIVE2D.md`** — this is
only the snapshot.*

This session ran under `away`. Decisions were made rather than asked; they are
listed below and each is one commit to overturn.

## State

**Everything is committed, pushed and deployed.** arisu has only `origin`.
Live at `.../arisu/?face=live2d`; the bundle ships in lain at `arisu/live2d/`
(4.2 MB, Natori only). The portrait renderer is still the default.

Working and verified this session:

- **Her jaw follows her own level, not the connection** — on both paths. The
  browser client and `Live.swift` both ran a fixed gain; both now expand
  against a running peak. A 12x change in level gives the same face.
- **The app's jaw follows her own voice**, tapped at the player rather than the
  microphone. It used to move while *he* talked.
- **No classroom, no gear, no debug bar** on her face. The canvas clears
  transparent, so lain's backdrop and her mood tint show through.
- **The five states are distinct** and blink and idle motion run.

## Decisions made without him — overturn any cheaply

- **The expander lives in the client and in `Live.swift`, not in the face.**
  The face cannot tell a measured level from Safari's synthetic envelope, so it
  passes host amplitude through on purpose. Expanding that envelope would
  freeze her mouth in the one case it exists for.
- **`PEAK_FLOOR` is 0.02.** At 0.05 it pinned exactly where a quiet stream's
  peak sits and the quiet case never expanded.
- **`FLOOR_RATIO` stays 0.5**, now measured on rms rather than inherited.
- **The gear went with the classroom.** It called `nextScene()` on a tap, so it
  swapped her character — a bug on her face, not decoration.
- **The overlay hides itself when framed** rather than being deleted. It costs
  nothing hidden and is the only hand test of the rig.
- Standing, from earlier sessions: expressions were picked by reading each
  `.exp3.json`, not by name; asleep forces the eyes shut in the hook; `nod` is
  deliberately unmapped; the `__arisuParam` probe stays.

## Open question — his, asked 2026-09-12 and unanswered

**Does Live2D go to the iPad app, or does it stay browser-only?** Web is *not*
meant to replace the app: Safari suspends on lock, so the app is still the
always-on seat. Live2D simply has not been taken there, and nothing is planned.

The interface is already right — the app drives a face through the same
`window.avatar` calls the Live2D page exposes, so no wiring changes. The
obstacle is shape: `FaceView` uses `loadFileURL` from the app bundle with read
access scoped to the face's own directory, which is why today's faces are one
self-contained file each with the portrait inlined. Live2D is a 4.2 MB tree.
Two ways out, neither chosen: copy the tree into the bundle and widen the
read-access scope, or point the webview at lain over the tailnet and trade
offline working for simplicity.

## Parked

- **Buying the character (step 6)** and **a live call to watch her mouth** —
  both cost money, so neither was done unsupervised.

## Next steps

1. Open `/arisu/live2d/` on the iPad — the page directly, not the framed
   `?face=live2d` view — and say whether the five expressions read right. They
   were chosen from parameter values and have never been watched.
2. Then a real call. The numbers are right on both paths, but the shaping was
   measured against speech, not her own TTS. **The app's fix is unrun.**
3. Step 6 — choose and buy the character, checking each listing for app use,
   modification and AI learning.

## Gotchas

Full list with the reasoning in `LIVE2D.md`. The four that cost the most time:

- **Never make `ossskkar/lain` public.** It carries Cubism Core, which is
  proprietary. The licence basis is that a private repo distributes to nobody.
- **Run `patch-sdk.sh` after unpacking a fresh SDK**, or nothing Arisu adds
  exists. It is idempotent.
- **She takes several seconds to appear**, and an empty canvas before then
  looks exactly like a broken build.
- **`requestAnimationFrame` stops when the page is not visible**, and a hidden
  browser pane counts.

Unchanged: `arisu/deploy.sh` is the dead Mac path; her voice and her memory
fail separately.
