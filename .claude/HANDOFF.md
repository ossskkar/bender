# Handoff — time machine, releases, autonomous builder (2026-10-02)

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
  the session runs it back to back from 12.0 on.
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
