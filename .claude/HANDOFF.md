# HANDOFF — Arisu (2026-09-10, evening)

*Her lain-side routes are `lain/docs/arisu-brain.md`; lain's own state is
`lain/.claude/HANDOFF.md`. The homelab handoff owns the Hermes side.*

## State

**Everything below is committed, pushed and deployed.** arisu at `6776947`,
lain at `c3e2814` on both remotes and on architect, both units active.

**The iPad is the app that matters.** He said so on 2026-09-10 and the copy on
the iPhone SE was removed that day, then put back when the SE became the second
seat in a room. Build and install with `xcodebuild` + `xcrun devicectl` against
a device id — no Xcode session, no cable ritual.

**Her face fills the glass.** The fit was a contain at 0.70 and is now a cover:
she reaches all four edges and the long sides crop. `fill` in the character
JSON is a multiple of that cover, 1.02 by default so drift and breath cannot
walk a black edge on. Her anchor is the middle of the screen.

**A room, and it works between two devices.** `lain/server/room.py` holds
membership, one *listener* whose microphone is the only live one, and a floor
lease. In group mode the ear reports what he said, the desk names one device to
answer — the character addressed by name, else whoever has been quiet longest —
and the rest are handed the words as context and stay quiet. Sessions mint per
character (`/arisu/realtime?character=`), so four screens are four people.

**Only the iPad and the iPhone SE can run it.** Both work phones (16 Pro, 16e)
carry a **Raboweb MDM profile that removes the trust button**, so a
developer-signed app cannot launch on either. Installed fine; will not run.

## Decisions & open questions

- **Deferred, his words, do not start it:** the iPad showing **up to six
  characters on a divided screen**, one conversation between them.
- **Settled 2026-09-10: the managed phones are closed. Do not reopen.** He said
  no to the $99/yr account, so TestFlight is out, and erasing a phone does not
  help — a supervised device re-enrols itself and reapplies the same
  developer-trust restriction. The iPad and the SE are the only seats.
- The room is **in memory**: a lain restart drops everyone to solo. Deliberate.
- Unchanged and still open: Chopper's better portrait, and Chopper's voice.

## Next steps

1. Put the room in group mode and try the iPad and the SE together:
   `ssh architect 'curl -s -X POST -d "{\"op\":\"mode\",\"mode\":\"group\"}" http://127.0.0.1:8888/arisu/room'`
2. **The lips still do not move to her own voice.** The jaw is driven by the
   microphone level (`Live.capture` sets `level` from the input tap), so it
   moves while *he* talks. Tap the output instead, publish it separately, and
   feed the face that while speaking. This was the agreed next piece of work.
3. Then visemes from a band analysis of her output audio, then mouth art —
   the renderer displaces scanline rows and cannot form a shape.

## Gotchas

- **A device new to the free provisioning profile fails to install** with
  `0xe8008012`. Rebuild with `-destination 'id=<that device>'` and
  `-allowProvisioningUpdates`; a `generic/platform=iOS` binary does not cover it.
- **The face renders about 30s after launch** in the simulator. A screenshot
  taken sooner is black and looks like a broken build.
- Free provisioning expires after **7 days** — reinstall to renew.
- `arisu/deploy.sh` is the dead Mac path. Ignore it.

## Resume

Brief as: the face fills the iPad edge to edge, and a group conversation works
between the iPad and the SE with one microphone and one voice at a time. Both
work phones are locked out by their employer's MDM and that is not fixable from
here. The next build is lip sync — her jaw currently follows his microphone,
not her own voice, which is why her mouth is still while she speaks.
