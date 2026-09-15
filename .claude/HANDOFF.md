# HANDOFF — Arisu (2026-09-13, evening)

*Progress lives in the lain Backlog (Arisu). Measurements and reasons: `LIVE2D.md`.*

## Her voice was corrected (lain `13fb209`, `a88eeee`)

Five journeys filed from one evening of listening; four are about how she talks.
Fixed in two places on purpose, because **a prompt is not a gate**:

- **Rules** (`lain/server/realtime.py`): one question, one answer; never narrate
  the work; no tool, file, branch or function name is ever spoken; `quiet` on
  its own is silence, not "Quiet."; a go-ahead is the whole instruction — do it
  and say what changed, never promise. A new `go_quiet` tool gives silence a
  name she can call.
- **Gate** (`lain/arisu/arisu-voice.js`, loaded by `index.html`, tested by
  `lain/tests/test_arisu_voice.js`): a response that is not the page's own is
  silenced while `think` is out; nothing gets through while hushed until her
  name; and a reply is asked for **once per turn, after the last tool answers**
  — asking per tool is where one turn became 81 spoken lines.

**Silenced, never cancelled.** `response.cancel` used to kill a response the
page had not asked for, and a function call rides inside its response — so it
killed the `think` call, and the question came back with no answer at all (ten
sessions at 22:25 do exactly that). The decision is taken at
`output_audio_buffer.started`, not at `response.created`: at creation there is
no way to know what the response carries. A silenced line is shown greyed and
logged with kind `silenced`.

**Every line she speaks is now on disk** (`lain/server/voice.py`):
`/var/lib/lain/arisu-voice.jsonl`, `GET /arisu/voice` for the last 400, `tail`
for the file itself. That is the answer to "she said something that is not in
the turn record", which before this had none. **Still open:** the stale line
itself ("round two of two", 19:10) was never reproduced, so the seq
high-water-mark half of that journey stays open — the log is what will catch it.

## State

Clean trees, all pushed. arisu head is this handoff (native command inbox in
`ff65675`). lain deployed to architect at `5ddd264` (speak-first: queue
`8166282`, reminders `18fc784`+persistence, brief `06d1e04`, check-ins
`a2263eb`, focus timer `ba82db0`, bedtime `80286cc`, `GET /services` `ba82db0`,
Sunday review `739822c`, state files `5ddd264`, MCP tools `aefede8`/`ba82db0`).

Built and verified on the desk (headless / live endpoints):
- **Speak-first command queue** (`lain/server/arisu.py`): `POST /arisu/say`,
  `GET /arisu/commands?character=` (pop-on-read, one screen gets each batch),
  in-memory on purpose; one spoken line, cut to 400 characters at a full stop.
  Every queued line leaves a **receipt in the journal** — `journalctl -u
  lain.service | grep 'arisu: queued'` is the only account of what she said of
  her own accord, and reading it is what found tonight's bugs.
- **Reminders** (`lain/server/reminders.py`): her `arisu_remind` MCP tool
  accepts "in N minutes/hours", HH:MM, ISO; fires into the queue. **Persistence
  proven in production**: schedule → restart lain.service → still known, file
  at `/var/lib/lain/arisu-reminders.json`. Where that file goes is now one
  shared rule (`lain/server/statefile.py`): beside the checkout when this
  process may write there, else the service's data dir.
- **Four time-of-day lines**, all composed (no Hermes turn), all queued:
  morning brief 08:00 (`brief.py`), Sunday review 19:00 (`weekly.py`), diary ask
  21:00 and habits ask 21:30 (`checkin.py`), bedtime 22:30 (`bedtime.py`). Each
  has its own env override and `"off"`; each fires only inside a **two-hour
  window**, and the day it last went out is on disk (`fired.py`), so a deploy
  never repeats one. The Sunday review fired live 2026-09-13 19:36 and its
  receipt is in the journal.
- **Focus timer** (`lain/server/timer.py` + `POST /arisu/timer`): she announces
  it, the queue stays empty until the bell, and rounds chain breaks. Verified
  live with a 1-minute 2-round timer: both bells fired at their offsets and were
  collected off the queue by a live screen.
- **Web page has the inbox**: Settings > Voice > **Play sample** (her current
  voice, through the real stream) and a 5s poll of `/arisu/commands` while
  live; drains one line at a time.
- **MCP**: `ainews_read`, `arisu_remind`, `ops_services`, `arisu_timer` — live:
  `hermes-gateway.service` is a *user* unit, so `systemctl --user restart
  hermes-gateway.service` (no sudo) reloads its lain child. Done 19:20.

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
  queue); an asleep Safari tab cannot speak, so only live screens drain it. A
  live screen is draining it right now — a line queued by hand was gone within
  seconds, which is how the timer bells were confirmed delivered.
- Time-of-day lines are env-configurable and default on (except in the test
  sandbox). House rules, all cheap to overturn: two-hour window, once a day on
  disk, nothing it cannot back with a number, under 400 characters, no nagging.
- Pending reminders are the persisted thing; a fired reminder becomes an
  ephemeral queue command and expires like any other.
- **Her turn history now persists again** (`arisu.json` in the service data
  dir): it had silently not been written since Sep 10 because the `lain`
  account cannot write the admin-owned checkout. That is continuity across a
  restart (last 8 exchanges), not memory — "Decide where her memory lives" is
  still Oscar's call, with the finding noted on the step.
- Mood entries already live in `data.json` `diary` as timestamped entries with
  metrics (95 on file, source `checkin`), so the mood journey's storage step
  has an answer in evidence; noted on the step, not ticked.
- Open: Oscar has not yet picked each character's face.

## Next steps

1. Oscar: build + install the app from Xcode, watch her say a reminder/brief
   on the iPad; tick "She speaks at the time, on the screen I am near" when
   proven (the web already covers Safari screens).
2. Her brain side of the asks: "She writes the entry and reads it back",
   "She ticks them", "She reads this week's headlines", "is anything down?" —
   realtime session work, and the tools are live on the gateway now.
3. Decide where her memory lives (the write failure is fixed; the choice is not).
4. Next speak-first line if the pattern holds: AI-news headlines at an hour he
   picks, and the get-to-know-me question — cadence needs his taste first.

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
- Commands are in-memory: a `lain.service` restart drops unplayed ones. Today's
  brief is NOT re-queued any more (it used to be: the day tracker is on disk now).
- A calendar time from a `Z` feed is UTC: say it through `gcal.local_time`,
  never by slicing the ISO string.

## Resume

"Read arisu/.claude/HANDOFF.md and the Arisu Backlog entry, then check
/arisu/commands for what the desk has queued and /arisu/diag for his last call."