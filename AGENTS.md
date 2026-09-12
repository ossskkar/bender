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
  with a `done` flag, plus notes.
- **Writing:** one op per `POST /backlog`, e.g.
  `{"op":"step_edit","project":"Arisu","journey":2,"step":4,"done":true}`.
  Ops and refs are documented in lain's `server/backlog.py`.
- Tick only what is verified. Built but unproven stays open.

Session detail: `.claude/HANDOFF.md`. Measurements and reasons: `LIVE2D.md`.
