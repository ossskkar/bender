# HANDOFF — Arisu (2026-09-12)

*lain's state is `lain/.claude/HANDOFF.md`; the homelab handoff owns Hermes.
**Every measurement and reason is in `LIVE2D.md`** — this is only the snapshot.*

## State

**Clean tree, everything pushed and deployed.** arisu has only `origin`; the
lain half is deployed to architect. Head `3c9aee7`, the session's work in
`a229281`, `b82c796`, `7246df7`.

Live at `.../arisu/?face=live2d`; bundle in lain at `arisu/live2d/` (4.2 MB,
Natori only). The portrait renderer is still the default.

Fixed and verified this session:

- **Her jaw follows her own level, not the connection**, on both paths. The
  browser client and `Live.swift` both ran a fixed gain — 0.10 on a quiet
  stream, 0.54 on a loud one. Both now expand against a running peak; a 12x
  change in level gives the same face.
- **The app taps her playback, not the microphone.** Her mouth used to move
  while *he* talked. Untested live — see Parked.
- **No classroom, no sample gear, no debug bar.** The canvas clears
  transparent, so lain's backdrop and mood tint show through.
- **An unguarded SDK teardown**, exposed by removing both sprites, which threw
  on an orientation change.
- **The five states are distinct**; blink and idle motion run.

## Decisions & open questions

- **The expander lives in the client and `Live.swift`, never in the face.** The
  face cannot tell a measured level from Safari's synthetic envelope, so it
  passes host amplitude through on purpose. Expanding that envelope would
  freeze her mouth in the one case it exists for.
- **`PEAK_FLOOR` 0.02** (0.05 pinned where a quiet stream's peak sits);
  **`FLOOR_RATIO` 0.5**, now measured on rms rather than inherited.
- **The gear went with the classroom** — it called `nextScene()` on a tap, so
  it swapped her character. The overlay is hidden-when-framed, not deleted.
- Standing: expressions picked by reading each `.exp3.json`, not by name;
  asleep forces the eyes shut in the hook; `nod` deliberately unmapped; the
  `__arisuParam` probe stays.
- **Open, his, asked 2026-09-12 and unanswered: does Live2D go to the iPad
  app?** Web is *not* replacing the app — Safari suspends on lock, so the app
  is still the always-on seat. The interface already matches; the obstacle is
  shape. `FaceView` uses `loadFileURL` from the bundle with read access scoped
  to the face's own directory, which is why today's faces are one
  self-contained file each. Live2D is a 4.2 MB tree. Either copy it into the
  bundle and widen that scope, or point the webview at lain over the tailnet
  and lose offline working. Neither chosen.

## Parked

- **Buying the character (step 6)**, and **a live call to watch her mouth**.
  Both cost money. The app's fix therefore builds clean and is exactly level
  independent on paper, but no real session has driven it.

## Next steps

The web page (lain `arisu/index.html`) is now the main surface: the iPad's
buttons, a settings panel, all eight Live2D models, and character tools.

1. Oscar calls her in Safari. Did her mouth move? Then
   `curl -s https://architect-server.tailaa64e9.ts.net:8443/arisu/diag` -- the
   `call` report lists which events arrived. Expect `output_audio_buffer.started`.
2. Same call: does she still open with fillers? Rules changed in lain
   `realtime.py` (commit "no filler before think").
3. Install the new build on the iPad, turn on Settings > Face > Live2D face.
4. Parked: room buttons on the web (page is not a room member), Play sample.
5. Costs money: habit add/remove test.

## Gotchas

Full list with reasoning in `LIVE2D.md`. The four that cost the most time:

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
