# Handoff — Singularity (2026-10-03)

## State
- **`89f15d6` + the handoff commit on `origin` and `timemachine`.** Working tree
  clean apart from old untracked `v1-build/*.vrm` and `flatface/sprites-*`,
  which are not this session's.
- **Walking into Singularity plays her arrival** — gather, dark, flash,
  shockwave — with no call. **Two taps** anywhere start or end the
  conversation; a long press summons her. The three gestures are separate:
  chaining them with `exclusively` left the single tap waiting on the double
  tap forever and the realm answered no touch at all.
- **The chant is carved in Elder Futhark** (`Runes.carve`) and struck half a
  second after the flash: lightning-white for a second, cooling iron over
  eight, the Latin line small beneath. Drawn last, over everything.
- **Her speech throws real waves**: a syllable is 1.1–3.3 (was 0.25–0.75),
  travelling half again as fast and wide, nearly twice as deep.
- **Layout**: apps on a smaller circle (0.295), the chosen app's actions on an
  outer ring at 0.44, the clockwork rim at 0.52. The actions are drawn the way
  the apps are — a lit point, the name in white, the shortcut under it — with
  no band and no background. Only the apps that are *not* chosen still trail
  their buttons down the spiral arms.
- **Rings open in place**: a tap that hits nothing opens the nearest ring,
  which stops turning, grows and goes white for six seconds.
- **All of the above is verified in the simulator only.** Nothing has been seen
  on the iPad.
- **The iPad install is blocked**: the device build signs again (Apple
  Development: ossskkar@gmail.com) and `xcodebuild -destination
  'generic/platform=iOS'` succeeds, but `devicectl install` fails with
  `kAMDMobileImageMounterDeviceLocked`. The iPad must be unlocked.

## Decisions & open questions
- Actions got their own ring rather than a band because he asked for no shared
  area and no background; the app circle's style is now the one style for
  anything orbiting the eye.
- Rings morph where they are instead of flying out to a flat card — the card
  was removed. Cheaper to read, nothing covers the eye.
- Open: the ring text is still one long line; whether it wants wrapping on the
  iPad's real width is unknown until it runs there.

## Next steps
1. Oscar: unlock the iPad and leave it on the home screen.
2. Me: `xcrun devicectl device install app --device 085B9100-31D5-5A2D-B44C-82D143A30ACA ~/Library/Developer/Xcode/DerivedData/Arisu-feqvuwnhdworpqgzcsphuntnhoex/Build/Products/Debug-iphoneos/Arisu.app`
3. Oscar: enter Singularity, hold to summon, double-tap to talk, tap a ring.
4. Me: tick the Singularity journey's remaining steps once he confirms.

## Gotchas
- **Screenshot timing lies.** The ring morph looked broken for several rounds
  because every shot landed at the instant the ring opened (open = 0). Read it
  at about twelve seconds in.
- Simulator builds must be ad-hoc signed (`CODE_SIGN_IDENTITY=-`); unsigned is
  a white screen. The simulator also renders ~5 s behind.
- The apps rotate, so a tap aimed from a screenshot often lands on the
  neighbour. Tap, shoot, read which label went magenta.
- An app with no deck buttons leaves the outer ring empty — that is correct,
  not a failure. Use Chrome or Spotify to see it.
- First build of a commit takes 3–7 min; cached after.

## Resume
"Read arisu/.claude/HANDOFF.md and continue with the next step."
