# HANDOFF — Arisu (2026-09-24)

*Progress lives in the lain Backlog (project Arisu). Earlier detail: git log.*

## State

- **Two screens, one app** (web `lain/arisu/` + iPad native): Voice (her 3D
  face, V30 default = `lain/arisu/vrm/arisu.vrm`) and Chat (`lain/arisu/chat.html`,
  terminal look, lain masthead "ARISUへようこそ！ · present day · present time",
  no glow). Same top-right row on both: history (clock), + new conversation,
  Voice|Chat toggle (waveform / `>_`). iPad shows chat.html full screen
  (`ChatScreen`, `?app=1`); its Voice half posts `close` to the `arisu` handler.
- **Chat backend:** `GET/POST /arisu/chat`, own Hermes session (40 turns, low
  reasoning), seeded from the current conversation in `/var/lib/lain/arisu-chat.jsonl`.
- **History (live, verified):** `lain/server/history.py` + `GET /arisu/history[?id=]`,
  `POST /arisu/chat/new`, `POST /arisu/voice/new` (resets voice Hermes bridges).
  Web page and iPad log voice lines + `call` start/end markers; voice log keeps
  200k lines. 53 conversations listed; a 45-line voice transcript renders.
  Skill: `lain/.claude/skills/arisu-history`.
- **iPad build** with all of the above installed 2026-09-24 (arisu 1fcfcbd);
  launches refused while locked. Not yet seen on the device by anyone.
  Chat keyboard verified in the iPad simulator.
- **Removed on request:** mute, hold-to-talk, group button (+ voice commands),
  meter, in-screen chat mode. Web has the iPad's 60 s idle hang-up and the
  "something to tell you, double-tap" offer for queued lines.
- **lain phone app** is separate from Arisu (merge tried, too slow, reverted).
- **Portrait animation (flatface): REJECTED** by Oscar 09-24 ("This is very
  bad"). Journey back in Backlog with that review. Do not resume unless asked.
  `flatface/make_poc.py` + `make_sprites.py` carry uncommitted edits from that
  session -- not this one's, left as found.
- **VRM:** V12-V30 built by `v1-build/tools/build.sh` (per version in
  `lain/arisu/vrm/MODEL.md`); he judged it far from the sheet. Buying or
  commissioning a model is undecided; his last word was **no** to the nit02
  cyber model (candidates in the Backlog step on the bought character).

## Decisions & open questions

- Voice and chat are separate UIs switched by the toggle (he chose this over an
  in-screen chat mode). "Clear" replaced by + (history makes hiding pointless).
- Old conversations split by gaps (chat 6 h, voice 10 min); old iPad calls
  only have the Hermes paraphrase, labelled in the transcript.
- + was never pressed on live (would move his thread into history). Untested.
- Open: which face Arisu keeps (VRM vs a bought/commissioned model).

## Next steps

1. Oscar checks the iPad: toggle, history, +, chat keyboard.
2. If + misbehaves: `curl -s -X POST https://architect-server.tailaa64e9.ts.net:8443/arisu/chat/new`
   then `curl -s https://architect-server.tailaa64e9.ts.net:8443/arisu/chat`.
3. Face: wait for his decision on buying/commissioning a model.

## Gotchas

- Deploy lain: push origin + architect, then
  `ssh architect 'git -C lain pull --ff-only && sudo -n systemctl restart lain.service'`.
- iPad: `xcodebuild ... -destination 'generic/platform=iOS' -allowProvisioningUpdates`,
  then `xcrun devicectl device install app --device 085B9100-31D5-5A2D-B44C-82D143A30ACA <app>`.
- Simulator: tap coords are device points (1032 wide); it wedges -- `xcrun simctl shutdown all`.
- `/arisu/commands` pops on read: never poll it in a test.
- Edit HTML with exact start/end markers and diff element ids before deploying
  (a loose cut once deleted the controls and settings for ~2 min).
- This handoff is shared by parallel sessions; merge, don't clobber.

## Resume

"Read arisu/.claude/HANDOFF.md and continue with what Oscar says about the iPad."
