# Arisu Canvas

Frameless, always-on-top windows on the Mac that Arisu pushes pages into.

No title bar, no chrome. Hold **⌘ and drag** to move one, **⌥ and drag** to
resize, **⌘⏎** to fill the screen it is on and ⌘⏎ again to put it back,
**Escape** to put it away until the next push. Position and size are remembered
per screen name.

⌘⏎ is not macOS full screen on purpose: that would give the window a Space of
its own, and the point of these is to sit on top of whatever he is doing.

**She is always on it.** The same voice visual the iPad draws — compiled from
the iPad's own `VoiceVisual.swift` and `Skin.swift`, not copied, so the two
cannot drift — tinted by what she is doing: indigo waiting, green hearing him,
magenta working, cyan talking.

She fills the window. A page she puts up is a **card centred on her**, 86% of
each side, so she shows all around it. The page's *own* background is stripped
(a user script sets `html,body` transparent) and the card behind it is what
provides the ground — translucent, so she moves through the page as well as
around it, while the text stays fully opaque and readable. `ARISU_PANEL` is how
solid the card is; 1 hides her behind the page completely, default 0.84.

Fading the web view itself was the first attempt and was wrong: view alpha
fades text along with background, and the page became unreadable.

Her level is **not** published by lain (`Live.swift`: read 20x a second by
whichever device holds the call, and sent nowhere). So the desk reads her
*phase* from `/arisu/state` — a long poll, so a line reaches it at once — and
shapes the level itself. The movement is hers; the waveform is a stand-in.
Publishing the real level is a small endpoint plus a 20 Hz stream from the
device in the call, worth doing only if the stand-in reads wrong.

`ARISU_FACE` picks one of the ten faces; the default is ribbon, as on the iPad.

    ./build.sh install           # builds, ad-hoc signs, copies to ~/Applications
    "$HOME/Applications/Arisu Canvas.app/Contents/MacOS/ArisuCanvas" desk vertical

One window per name. The name is the address — nothing registers it, the first
push creates it.

**Several things at once.** A comma-separated `url` lays them out as a grid, up
to six — one fills the window, two sit side by side, three or four make a
square. Verbs act on the first panel unless the arg starts with a panel number;
`read` returns every panel, labelled; `find` and `click` search all of them and
report which one matched.

**Filling a screen.** ⌘⏎ toggles it, or she does it with `fill` — and `fill`
takes a monitor number, which is the point of a window you can send to the
vertical screen.

## Arisu driving it

Two tools on her Hermes brain, so it works from every client at once — the web
face and the iPad app share that brain and neither needed a change.

- `screen_show(url, screen="desk", title="")`
- `screen_do(action, screen="desk", arg="")` — `back forward reload top bottom
  up down find click read`

`read` answers with the page's text, which is how she sees what she put up;
`click` answers with what it pressed, or that it matched nothing. Verbs and
never JavaScript from the wire: this window holds his signed-in sessions, and a
page she has been asked to read is where an instruction would be planted.

Registered in `~/.hermes-arisu/config.yaml` under
`mcp_servers.lain.tools.include` on architect; Hermes must stay under 64 tools
in total.

## Putting something on a screen

    curl -sk -X POST https://architect-server.tailaa64e9.ts.net:8443/screens \
      -H 'Content-Type: application/json' \
      -d '{"name":"desk","url":"/systems/systems.html","title":"Project 100K"}'

A path is resolved against lain; an absolute URL is loaded as it comes; a path
that exists on this Mac, or a `file:` URL, is loaded as a local document — PDFs
and images render in WebKit without help. Blank a
screen with `{"name":"desk","clear":true}`, and read one back with
`GET /screens?name=desk` (or `GET /screens` for all of them).

Content lives in lain's `server/screens.py`, deliberately *not* in her speech
queue: `/arisu/commands` is pop-on-read so a reminder is announced once, which
is right for a line and wrong for a canvas. A canvas is a standing fact — it
has to survive being read, be read by several clients, and still be there after
a restart.

## Why AppKit and not Tauri

Oscar, 2026-10-04, asked for the option with the most control over the UI. The
content is already web, so the only genuinely native part is the window — and
that is the part Tauri wraps in a smaller vocabulary than AppKit's. Here the
window is an `NSWindow` with nothing hidden, and there is no Rust toolchain and
no 200 MB runtime in the way.

## At login

`com.oscar.arisu-canvas.plist` → `~/Library/LaunchAgents/`, then
`launchctl load`. It runs the copy in `~/Applications`, never the one in the
checkout: macOS TCC refuses a launchd agent access to `~/Documents`.

## Checking it

`screencapture` is refused to an unprivileged process, so the app can snapshot
its own page instead — no Screen Recording permission needed:

    ArisuCanvas desk --shot /tmp/shots     # draws for 8s, writes desk.png, quits

## Not done yet

- Click-through (`ignoresMouseEvents`). It needs a global hotkey to undo, and
  that needs Accessibility permission — not worth it until he asks.
- Typing into a page. `find` and `click` exist; `type` does not.
- Per-panel layout control: the grid is chosen from the count, not arranged.
- Cross-origin iframes are out of reach, and PDFs render but cannot be driven.
