# Arisu's deck

The Mac half of the iPad's button grid. `deck.py` holds the retired macropad's
action executor and its 36 bindings, flattened into `buttons.json`; the iPad
draws them and presses them.

## How the iPad reaches it

`deck.py` listens on `127.0.0.1:8887`. The Mac's existing `tailscale serve`
rule on `:8443` already proxied there — it pointed at a dead port — so the iPad
reaches the deck at

    https://oscars-macbook-pro.tailaa64e9.ts.net:8443/deck

with no new serve rule and no change to the machine. **Tailnet only. Never put
this on a funnel** — see the safety note in `deck.py`'s docstring.

## Running it

    launchctl load -w ~/Library/LaunchAgents/com.oscar.arisu-deck.plist

Copy `com.oscar.arisu-deck.plist` there first. Without it the deck only runs
while something is holding the process open, and the iPad's grid goes grey.

    ./deck.py selftest     # the buttons load, every action type validates
    ./deck.py list         # print the buttons
    ./deck.py press mac.k1 # execute one from the shell

## Endpoints

| | |
|---|---|
| `GET /deck` | the buttons the iPad draws |
| `POST /deck/run` `{"id": "mac.k1"}` | execute that button |
| `POST /deck` `{"buttons": [...]}` | replace the whole set |

`/run` takes an **id and never an action**, so anything that can reach the port
can press a button he already wrote but cannot run something new.

## Gotchas

- **`keys` actions need `~/Applications/MacropadType.app`**, which is the bundle
  that actually holds Accessibility on this Mac. It kept its name on purpose:
  renaming it means granting Accessibility again. Seven of the 36 buttons are
  `keys`.
- The log directory `~/Library/Logs/macropad` is where `press` leaves its
  result file. It exists because the macropad ran; do not delete it.
- Python is pinned to `/usr/local/bin/python3.11` — `python3` on PATH here is
  an Xcode 3.7 from 2020.

## The store, and the TCC hang (2026-09-27)

`buttons.json` beside this file is the **seed**, not the live store. The live one
is `~/.local/share/arisu-deck/buttons.json` (`ARISU_DECK_BUTTONS` overrides,
`serve --buttons` wins over both), because launchd may not read `~/Documents`
and a denied `open()` on macOS does not fail -- it hangs, forever, inside
`open()`. The symptom is exact: `GET /` answers in a millisecond and
`GET /deck` never answers at all, which on the iPad's rail is a spinner that
never stops.

**Moving the store was not enough.** Under launchd the same `open()` hangs on
`~/.local/share` too, while the identical command run from a terminal answers
instantly -- so the job has no file-access consent at all, not just none for
Documents. That consent is a System Settings grant nobody but Oscar can give:
Privacy & Security ▸ Files and Folders (or Full Disk Access) for
`/usr/local/bin/python3.11`, then
`launchctl kickstart -k gui/501/com.oscar.arisu-deck`.

Until then the deck answers nothing and the iPad's rail says so after 8s.
