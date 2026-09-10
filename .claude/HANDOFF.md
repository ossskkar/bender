# HANDOFF — Arisu (2026-09-10, night)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

## State

**Everything below is committed, pushed and deployed.** arisu at `e63c865`,
lain at `716dfc6` on both remotes and on architect, both units active.

**She runs in Safari now, with voice, and the work phones are solved.** He
confirmed it on the **iPhone 16e** the same evening: her face comes up and she
hears him and answers. The address is
`https://architect-server.tailaa64e9.ts.net:8443/arisu/`, `?c=chopper` for the
other one. No app, no signing, so the MDM restriction never applies. Full
detail and every gotcha are in the **`arisu-in-safari` skill**.

The trick is the transport. A browser cannot set an Authorization header on a
WebSocket, so `Live.swift`'s path is unavailable; the browser client uses
WebRTC and `/arisu/realtime?transport=webrtc` mints the same session minus the
PCM format fields. `faces/build.py` now emits every face to the app bundle
*and* to `lain/arisu/`, so the two copies cannot drift.

**The iPad is still the always-on seat.** Safari suspends when the phone locks,
so the browser is open-it-and-talk. That is a limit of the surface, not a bug.

**Her face fills the glass** and **the room works between two devices** —
unchanged from the last session, both still true.

## Decisions & open questions

- **Settled 2026-09-10: the managed phones are done, by browser. Closed.** No
  $99 account, no TestFlight, and erasing a phone does nothing — a supervised
  device re-enrols and reapplies the restriction. Do not reopen.
- **Deferred, his words, do not start it:** the iPad showing **up to six
  characters on a divided screen**, one conversation between them.
- The room is **in memory**: a lain restart drops everyone to solo. Deliberate.
- The browser client is **solo only** — it does not join the room. Whether it
  should is open and has not been asked.
- Unchanged and still open: Chopper's better portrait, and Chopper's voice.

## Next steps

1. **Lip sync, and the browser already proves the fix.** `Live.swift` drives
   the jaw off the *input* tap, which is why her mouth moves while he talks and
   is still while she speaks. The browser client puts an analyser on the output
   stream instead and her mouth is right. Port the idea into the app.
2. Then visemes from a band analysis of her output audio, then mouth art — the
   renderer displaces scanline rows and cannot form a shape.
3. Optional, unasked: let the browser client join the room, so the 16e can be a
   third seat beside the iPad and the SE rather than its own conversation.

## Gotchas

- **A device new to the free provisioning profile fails to install** with
  `0xe8008012`. Rebuild with `-destination 'id=<that device>'` and
  `-allowProvisioningUpdates`; a `generic/platform=iOS` binary does not cover it.
- **The face renders about 30s after launch** in the simulator. A screenshot
  taken sooner is black and looks like a broken build.
- Free provisioning expires after **7 days** — reinstall to renew.
- **arisu has only `origin`**, unlike lain. There is no `architect` remote here;
  pushing one to both is an error, not a habit.
- `arisu/deploy.sh` is the dead Mac path. Ignore it.
- **Her voice and her memory fail separately.** Voice is OpenAI, `think` is
  Hermes on the Anthropic credit. She can talk fluently and still fail every
  factual question.

## Resume

Brief as: she now runs in Safari over the tailnet with full voice, which put
her on the work iPhone 16e that the MDM had locked out — that problem is closed
and should not be reopened. The iPad is still the always-on seat because Safari
suspends on lock. The next build is lip sync in the app, and the browser client
already demonstrates the fix: tap her output, not the microphone.
