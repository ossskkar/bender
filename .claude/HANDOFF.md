# HANDOFF — Arisu (2026-09-13, evening)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## State

Clean trees, all pushed. arisu head is this handoff (native command inbox in
`ff65675`). lain deployed to architect at `a2263eb` + `6fe464d` (speak-first:
queue `8166282`, reminders `18fc784`+persistence, brief `06d1e04`, check-ins
`a2263eb`, MCP tools `aefede8`, Play sample `6342e6e`).

Built and verified on the desk (headless / live endpoints):
- **Speak-first command queue** (`lain/server/arisu.py`): `POST /arisu/say`,
  `GET /arisu/commands?character=` (pop-on-read, one screen gets each batch),
  in-memory on purpose; 400-char cap. Verified live on architect.
- **Reminders** (`lain/server/reminders.py`): her `arisu_remind` MCP tool
  accepts "in N minutes/hours", HH:MM, ISO; fires into the queue. **Persistence
  proven in production**: schedule → restart lain.service → still known, file
  at `/var/lib/lain/arisu-reminders.json` (the `lain` account cannot write the
  admin-owned checkout; the default falls back to /var/lib/lain).
- **Morning brief** (`lain/server/brief.py`): composed from plan ticks, 100K
  line, first calendar event, birthdays — no Hermes turn. 08:00 default,
  `LAIN_ARISU_BRIEF` overrides, "off" silences. Fired live on architect at boot.
- **Evening check-ins** (`lain/server/checkin.py`): diary ask 21:00, habits ask
  21:30 (`LAIN_ARISU_DIARY_ASK` / `LAIN_ARISU_HABITS_ASK`, "off" disables
  independently). The write-backs (diary entry, habit ticks) are the realtime
  session's steps, still open.
- **Web page has the inbox**: Settings > Voice > **Play sample** (her current
  voice, through the real stream) and a 5s poll of `/arisu/commands` while
  live; drains one line at a time.
- **MCP**: `ainews_read` tool; `arisu_remind` tool; the ops/backlog/room tools
  from earlier sessions.

Built, type-checked, **not yet built on device** (needs Oscar's Xcode):
- **Native app command inbox** (`native/Arisu/Live.swift`, `Brain.swift`):
  5s poll of `/arisu/commands?character=`, plays via her own session with
  "say exactly this" instructions, one line at a time (waits for speaker-dry
  via `drained()`/`response.done`, 60s failsafe), keeps polling while the
  socket is dormant so a reminder can wake her, does NOT reconnect when the
  session is live so her context survives. Whole module type-checks against
  the iOS simulator SDK (warnings only in pre-existing code). Verify on device
  before ticking anything that depends on it.

## Decisions & open questions

- Speak-first delivery is the **web page and iPad app** (both poll the same
  queue); an asleep Safari tab cannot speak, so only live screens drain it.
- Reminders/brief/asks are time-of-day (the journey allows it) and
  env-configurable; all default on except in the test sandbox.
- Pending reminders are the persisted thing; a fired reminder becomes an
  ephemeral queue command and expires like any other.
- Open: `arisu.json` conversation history lives at `~/lain/arisu.json`, which
  the `lain` service account cannot write (mtime Sep 10) — memory persistence
  has been failing silently since the unit ran as `lain`; the "Decide where
  her memory lives" step should fold this in.
- Open: her MCP tool list is cached by `hermes-gateway.service`; the new
  tools live only after it restarts (sudo not granted to this session).
- Open: Oscar has not yet picked each character's face.

## Next steps

1. Oscar: build + install the app from Xcode, watch her say a reminder/brief
   on the iPad; tick "She speaks at the time, on the screen I am near" when
   proven (the web already covers Safari screens).
2. Her brain side of the asks: "She writes the entry and reads it back",
   "She ticks them", "She reads this week's headlines" — realtime session work.
3. "Reminders survive a reload" is ticked; "survive a restart" proven live.
4. Restart `hermes-gateway.service` so she sees `ainews_read`/`arisu_remind`.
5. Decide where her memory lives (folds in the arisu.json write failure above).

## Gotchas

- Never make `ossskkar/lain` public (Cubism Core). Run `patch-sdk.sh` after a fresh SDK.
- Re-vendor after a face change: build in `arisu/live2d/CubismSdkForWeb/Samples/TypeScript/Demo`
  (`npm run build:prod`), copy `dist/index.html`, `dist/assets/*`, `dist/arisu-*.js`
  into `lain/arisu/live2d/`; a new model also needs a still in `thumbs/`.
- Launching the iPad app mints a paid realtime session at once (`Pet.running` starts true).
- rAF stops in a hidden pane; test in headless Chrome over CDP (`--headless=new
  --use-angle=swiftshader`). The stock SDK `alert()` froze pages; patched out.
- Oscar's Chrome has acceleration off; use Safari. Mac muted = silent Arisu.
- `/arisu/diag` is in memory: a lain restart empties it.
- Commands are in-memory: a `lain.service` restart drops unplayed ones, and
  re-queues today's brief (once per boot) — both by design.

## Resume

"Read arisu/.claude/HANDOFF.md and the Arisu Backlog entry, then check
/arisu/commands for what the desk has queued and /arisu/diag for his last call."