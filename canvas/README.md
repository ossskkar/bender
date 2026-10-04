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
magenta working, cyan talking. With nothing up she fills the window; with a
page up she keeps a band across the top and the page takes the rest.

That band is a decision, not a default. An opaque page and an animation behind
it cannot both have the middle: a lain page carries its own near-black ground,
so under it she is not dim, she is gone. The alternatives are a corner orb, or
a translucent page — both change what he reads, so they are his call.

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
- Arisu pushing by voice: she needs a `screen_show` MCP tool and that tool
  listed in her Hermes profile on architect. Anything else can push today.
