# HANDOFF — Arisu (2026-09-23)

*Progress lives in the lain Backlog (Arisu → "I see Arisu's Live2D face react
to the conversation" and "Arisu appears as a 3D model…"). Earlier detail is in
git history.*

## This session (chat and apps, 2026-09-23) -- separate from the shopping thread below

- **Two screens, one app, a Voice | Chat toggle** (icons: waveform / `>_`, top
  right) on web and iPad. Voice = her face. Chat = `lain/arisu/chat.html`, a
  terminal page: lain masthead (ARISUへようこそ！ · present day · present time, no
  glow), icon buttons, a real visible textarea (the hidden-textarea trick did
  not raise the iPad keyboard -- fixed; keyboard verified in the iPad simulator).
  iPad shows chat.html full screen (`ChatScreen`, no iOS bar); its Voice half
  posts `close` to the `arisu` WKScriptMessageHandler.
- Chat backend: `GET/POST /arisu/chat`, own Hermes session (40 turns, low
  reasoning), seeded from `/var/lib/lain/arisu-chat.jsonl`. Test lines of mine
  ("ping", 3ED6FF...) are in that log; lain-owned, cannot delete.
- **Removed on request:** mute, hold-to-talk, group button (+ their voice
  commands), meter, the in-screen keyboard chat mode (tried and rolled back).
- **Web gained the iPad's** 60 s idle hang-up and "something to tell you,
  double-tap" for queued lines (polls only while visible; reads empty the queue).
- **lain phone app is separate again** (Arisu tab tried, made lain slow, removed).
- アリス icon on both apps; web remembers the last face per device.
- Parked on 09-23: history/sessions/new-conversation feature (quoted, he chose
  the terminal chat instead).

## State

- (shopping thread) Nothing in this repo changed in that session.
- **Character shopping (new thread).** Oscar asked for a model to buy for
  Arisu and rejected four shortlists. The brief settled through the
  rejections: a **cool cyber or robot adult woman, anime style, fully
  dressed** — not cute, not sexualised, and not dull office-wear either.
  BOOTH and nizima surveyed; the full record, every candidate with its link
  and why it was rejected, is in the new Backlog step *"Decide Arisu's bought
  character, or commission one"* (journey 2). Read that, not this file.
  His last word was **no** to the nit02 cyber model — the hunt is still open.
- **VRM thread (carried over, unchanged today).** Her default is still V30
  (`lain/arisu/vrm/arisu.vrm`); latest version is always the default. Web page
  matches the iPad (lain df5a49d, bf5d2d4). Build chain:
  `sh v1-build/tools/build.sh <out.vrm>` then
  `python3 tools/publish_version.py N stem render.png`.
- **Remote Control is now on** for new sessions by default, and for this one.
  Idle sessions refuse it — they connect when next woken with a message.

## Decisions & open questions

- **Licence is not a constraint.** Arisu is private — his machines and phones
  over the tailnet, never published — so an ordinary VTuber licence is fine.
  Do not pay extra for commercial or embedding rights, and do not rule a model
  out over them. Two turns were wasted on this.
- **Unresolved contradiction:** `arisu/LIVE2D.md` says 3D/VRM is superseded by
  Live2D, but the VRM Arisu (V30) is what actually ships as her face today.
  Nobody has decided which track the bought character belongs to. Ask him.
- Unexplored when the session ended: nizima's 限定1点 tier (~¥30k–200k), where
  the adult android models live, and nizima's order-made commission system
  (~¥50k–180k). Links in the Backlog step.

## Next steps

1. Ask Oscar which track the bought character is for — Live2D or the VRM.
2. Open the two nizima 限定1点 androids named in the Backlog step and show him
   the artwork. Both match the brief on their titles; neither was opened.
3. If he rejects those too, price a commission on nizima and put the number
   in front of him.

## Gotchas

- **Judge every candidate by looking at the artwork, never by the title.**
  Japanese product titles hide both the outfit and the age. Three wrong
  shortlists came from reading titles: "お酒好きのお姉さん" and "ダークエルフメイド"
  read as neutral in text and are not.
- Search terms that waste time: メカ (returns chibi animals), 露出控えめ (no
  results), スーツ (mostly male). Terms that work: サイバーパンク, アンドロイド,
  近未来, 軍用, 電脳.
- nizima renders blank in the sandboxed browser pane. `get_page_text` and
  JavaScript work; for pictures, pull the `storage.googleapis.com` image URLs
  out of the DOM and open them directly.
- `backlog_project` and `backlog_step_add` on Arisu both blow the token limit
  and spill to a file — grep that file rather than reading it.
- `v1-build/*.vrm` and `v1-build/tools/*.py` are untracked leftovers from the
  V5–V30 sessions. Not this session's; left alone.
- The shared-notes write (`arisu-look-adult-not-cute`) committed but reported
  `pushed: false`. Check it reached architect.

## Resume

"Read arisu/.claude/HANDOFF.md, then the Arisu Backlog step 'Decide Arisu's
bought character, or commission one', and continue the character hunt."
