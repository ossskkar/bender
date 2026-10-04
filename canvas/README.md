# Arisu Canvas

Frameless, always-on-top windows on the Mac that Arisu pushes pages into.

No title bar, no chrome: the page fills the window edge to edge. Hold **⌘ and
drag** to move one, **⌥ and drag** to resize, **Escape** to put it away until
the next push. Position and size are remembered per screen name.

    ./build.sh install           # builds, ad-hoc signs, copies to ~/Applications
    "$HOME/Applications/Arisu Canvas.app/Contents/MacOS/ArisuCanvas" desk vertical

One window per name. The name is the address — nothing registers it, the first
push creates it.

## Putting something on a screen

    curl -sk -X POST https://architect-server.tailaa64e9.ts.net:8443/screens \
      -H 'Content-Type: application/json' \
      -d '{"name":"desk","url":"/systems/systems.html","title":"Project 100K"}'

A path is resolved against lain; an absolute URL is loaded as it comes. Blank a
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
- Arisu pushing by voice: she needs a `screen_show` MCP tool and that tool
  listed in her Hermes profile on architect. Anything else can push today.
