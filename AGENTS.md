# Agents: start here

**Project state and progress live in the lain Backlog — the single source of
truth.** Not in this repo's handoff, `LIVE2D.md` or your memory.

This repo is the Backlog project **Arisu** (her brain is in lain,
`server/arisu.py`).

- **Read it before starting work:**
  `https://architect-server.tailaa64e9.ts.net:8443/backlog` on the tailnet,
  `curl -s http://127.0.0.1:8888/backlog` on architect, or the
  `backlog_project` tool if you have lain's MCP.
- **Shape:** project → user journeys (what Oscar can do once it ships) → steps
  with a `done` flag, plus notes. Every journey also sits in a **kanban column**
  — `backlog`, `doing`, `review`, `done` — which is how the Backlog popup shows
  the project: four columns of journey cards.
- **Writing:** one op per `POST /backlog`, e.g.
  `{"op":"step_edit","project":"Arisu","journey":2,"step":4,"done":true}`.
  Ops and refs are documented in lain's `server/backlog.py`.
- **Columns are yours to move — except `done`.** `doing` while it is being
  built, `review` when it is finished and waiting for him, and `journey_status`
  takes `by` so the journal says who moved it. **Never move a journey to `done`
  on your own judgement:** the op refuses it without `confirmed_by`, and you
  send `confirmed_by:"oscar"` only when he has actually said so in that
  conversation. A journey nobody has placed reads off its own steps, so ticking
  steps carries it as far as review and no further.
- **Work that lands in `review` explains itself.** Before a journey goes there,
  its notes say in two short lines what it does and how to try it:
  `What it does: …` and `Try it: …`, plain words, no jargon. Review is his
  decision queue — he is being asked to approve the thing, and a bare title is
  not something anyone can approve.
- Tick only what is verified. Built but unproven stays open.

Session detail: `.claude/HANDOFF.md`. Measurements and reasons: `LIVE2D.md`.
