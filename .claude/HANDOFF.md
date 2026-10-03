# Handoff — Singularity, the coders, and her music (2026-10-03)

## Singularity (shipped, iPad install pending)
- **Walking in plays her arrival** -- gather, dark, flash, shockwave -- with no
  call. **Two taps** anywhere start or end the conversation; a long press still
  summons her. The three gestures are separate now: chaining them with
  `exclusively` left the single tap waiting on the double tap forever and the
  realm answered no touch at all.
- **The chant is carved in Elder Futhark** (`Runes.carve`) and struck half a
  second after the flash: lightning-white for a second, cooling iron over
  eight, the Latin line small beneath. Drawn last, over everything.
- **Her speech throws real waves**: a syllable is 1.1-3.3 (was 0.25-0.75),
  travelling half again as fast and wide, nearly twice as deep.
- **Layout**: apps on a smaller circle (0.295), the chosen app's actions on an
  outer ring at 0.44, the clockwork rim out at 0.52. The actions are drawn the
  way the apps are -- a lit point, the name in white under it, the shortcut
  below -- with no band and no background (Oscar, 2026-10-03). Only the apps
  that are not chosen still trail their buttons down the spiral arms.
- **Rings open in place on a tap**: they record their own geometry while
  drawing and a tap that hits nothing opens the nearest one, which stops
  turning, grows and goes white for six seconds. Verified in the simulator --
  the earlier shots that looked like nothing happened were taken at the instant
  the ring opened; read it at about twelve seconds in.
- **The iPad install is blocked**: iOS will not mount the developer image while
  the device is locked. The build is ready; unlock and install.

## State
- **Releases** are annotated tags `arisu-N.N`: 0.1 First form (`b089d8e`, the
  first commit) … 10.0 Singularity, 11.0 Time machine (`2fe294c`). Catalog,
  highlights and tours live in `native/Arisu/Releases.swift`.
- **Time machine** (`deck/deck.py`, see `deck/README.md`): `/deck/travel` builds
  any `native/` commit from the bare mirror `~/.local/share/arisu-timemachine/arisu.git`
  (git remote `timemachine`) and installs it on the iPad (devicectl) or the
  simulator, then opens it. All 11 releases build; travel from inside the app
  verified in the simulator (11.0 → 10.0). Deck restarted, serving it.
- **Tours**: `TourOverlay` + `.tourSpot("name")`; a new version starts its tour
  once (`arisu.touredVersion`). 11.0's 10-stop tour checked in the simulator.
- **Agent** `../.claude/agents/arisu-builder.md` ships one release per run;
  12.0 At a glance, 13.0 Chat at a glance, 14.0 Landscape, 15.0 Next line done.
  The scheduled task `agent-loops` runs it from now on (see ../.claude/HANDOFF.md).
- **The iPad's installed Arisu expired 2026-10-02 01:34** (free profile). Xcode
  has no Apple ID signed in, so no device build signs until Oscar signs in.

## Decisions
- Time machine lives on the Mac deck, not in the app: one binary cannot hold
  old code; the deck builds and installs. Mirror in ~/.local/share (launchd/TCC).
- Old builds (pre-11.0) return via the Safari page `/deck/travel`.
- Tours start by themselves once per new version; SKIP ends them.
- Agent never installs on the iPad; the session decides.

## Next steps
1. Oscar: Xcode → Settings → Accounts → + → Apple ID (Personal Team).
2. `python3.11 deck/deck.py travel latest` — signs, installs, opens on the iPad.
3. Travel on the iPad to 0.1 and back via the Safari page.

## Gotchas
- Simulator builds must be ad-hoc signed (`CODE_SIGN_IDENTITY=-`); unsigned = white screen.
- Simulator renders ~5 s behind; taps right after launch are lost.
- Sim prefs: `defaults write "<data container>/Library/Preferences/com.oscar.arisu" …`.
- `.git/refs/remotes/origin/main 2` is a stray duplicate ref; `git clone --mirror` chokes on it.
- First build of a commit takes 3–7 min; cached after.

## Resume
"Read arisu/.claude/HANDOFF.md and continue with the next step."
