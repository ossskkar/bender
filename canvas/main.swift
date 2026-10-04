// Arisu Canvas -- frameless always-on-top windows on the Mac that Arisu pushes
// pages into.
//
// Why AppKit and not Tauri (Oscar, 2026-10-04, "the one that gives the most
// control over the UI"): the content is already web -- every page worth putting
// up is a lain page -- so the only part that has to be native is the *window*,
// and that is exactly the part Tauri wraps in a smaller vocabulary than the one
// underneath it. Here the window is an NSWindow with nothing hidden: any level,
// borderless, clear background, joins every Space, no title bar and no chrome
// of any kind -- the page fills it edge to edge. Web UI inside, real AppKit
// outside, no Rust toolchain and no 200 MB runtime.
//
// Moving one: hold ⌘ and drag anywhere. Resizing: hold ⌥ and drag. Escape puts
// a window away until the next push.
//
// One window per screen name given on the command line; the name is how Arisu
// addresses it. Content comes from lain's /screens channel, polled rather than
// pushed because a poll of a 100-byte JSON every two seconds costs nothing and
// a socket that has to reconnect through a sleeping laptop costs attention.
//
//   swiftc main.swift -o canvas            # or ./build.sh for the .app
//   ./canvas desk vertical

import Cocoa
import WebKit

let BASE = ProcessInfo.processInfo.environment["LAIN_URL"]
    ?? "https://architect-server.tailaa64e9.ts.net:8443"
let POLL = 2.0

// What lain says a screen is showing. `rev` is the whole point: it moves on
// every push, including a push of the same URL, so "put it up again" works and
// a page he is reading is never reloaded underneath him by a poll that found
// nothing new.
struct ScreenState: Decodable {
    let url: String
    let title: String
    let rev: Int
}

struct ScreenReply: Decodable {
    let screen: ScreenState?
}

// MARK: - the chrome

// There is none. No title bar, no strip, no buttons (Oscar, 2026-10-04): the
// page fills the window edge to edge.
//
// That leaves nothing to drag, and `isMovableByWindowBackground` does not help
// because WKWebView eats the mouse before the window sees it. So a transparent
// sheet sits over the whole window and claims the mouse *only while a modifier
// is held* -- ⌘ to move, ⌥ to resize from wherever the drag started. The rest
// of the time `hitTest` returns nil and the sheet is not there at all, so the
// page is fully clickable and scrollable.
final class Grab: NSView {
    private var origin = NSPoint.zero
    private var start = NSRect.zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let mods = NSEvent.modifierFlags
        return mods.contains(.command) || mods.contains(.option) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        if NSEvent.modifierFlags.contains(.command) {
            w.performDrag(with: event)         // AppKit runs the whole drag
            return
        }
        origin = NSEvent.mouseLocation
        start = w.frame
    }

    // ⌥-drag resizes: the bottom-left corner stays put and the window grows
    // with the mouse, which is the one gesture that needs no visible handle.
    override func mouseDragged(with event: NSEvent) {
        guard let w = window, !start.isEmpty else { return }
        let now = NSEvent.mouseLocation
        let width = max(200, start.width + (now.x - origin.x))
        let height = max(140, start.height - (now.y - origin.y))
        w.setFrame(NSRect(x: start.minX, y: start.maxY - height,
                          width: width, height: height), display: true)
    }

    override func mouseUp(with event: NSEvent) { start = .zero }
}

// Borderless windows refuse to become key by default, which would make every
// page read-only -- no scrolling with the keyboard, no text fields, no links
// that need focus.
final class Frameless: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Escape puts it away. With no title bar there is no close button, and a
    // widget he cannot dismiss is one he ends up quitting the whole app to be
    // rid of. It comes back by itself the next time she pushes to this name.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { orderOut(nil) } else { super.keyDown(with: event) }
    }
}

// MARK: - a canvas

final class Canvas: NSObject, WKNavigationDelegate {
    let name: String
    let window: Frameless
    private let web: WKWebView
    private var rev = -1
    private var timer: Timer?

    init(name: String) {
        self.name = name

        let conf = WKWebViewConfiguration()
        web = WKWebView(frame: .zero, configuration: conf)
        // Transparent so a page with no background of its own lets the desk
        // through. Private API by name only; it has been this key since 2014
        // and the failure mode if it ever goes is an opaque white window.
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }

        window = Frameless(contentRect: Canvas.savedFrame(name),
                           styleMask: [.borderless, .resizable],
                           backing: .buffered, defer: false)
        super.init()

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        // On every Space and not shuffled by Mission Control: a widget that
        // vanishes when he switches desktop is not a widget.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                     .fullScreenAuxiliary]
        window.delegate = self
        window.title = "Arisu Canvas: \(name)"

        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(white: 0.04, alpha: 0.82).cgColor

        let grab = Grab()
        for v in [root, web, grab] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        root.addSubview(web)
        root.addSubview(grab)                  // over the page, invisible
        window.contentView = root

        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: root.topAnchor),
            web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            grab.topAnchor.constraint(equalTo: root.topAnchor),
            grab.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            grab.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            grab.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        idle()
        window.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: POLL, repeats: true) {
            [weak self] _ in self?.fetch()
        }
        fetch()
    }

    // MARK: content

    private func idle() {
        web.loadHTMLString("""
        <body style="margin:0;font:12px -apple-system;color:#5a5a5a;
                     display:flex;align-items:center;justify-content:center;
                     height:100vh;background:transparent">
          waiting for \(name)
        </body>
        """, baseURL: nil)
    }

    private func fetch() {
        guard let url = URL(string: "\(BASE)/screens?name=\(name)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let reply = try? JSONDecoder().decode(ScreenReply.self,
                                                        from: data)
            else { return }
            DispatchQueue.main.async { self.apply(reply.screen) }
        }.resume()
    }

    private func apply(_ state: ScreenState?) {
        guard let state else {
            // Cleared. Back to the idle card rather than the last page, so a
            // blanked screen does not keep claiming yesterday is current.
            if rev != -1 {
                rev = -1
                idle()
            }
            return
        }
        guard state.rev != rev else { return }
        rev = state.rev
        window.title = state.title.isEmpty ? state.url : state.title
        // A path means a lain page; an absolute URL is taken as it comes.
        let target = URL(string: state.url, relativeTo: URL(string: BASE))
        if let target {
            web.load(URLRequest(url: target))
        }
        // One line per push. "Did it actually arrive?" is otherwise only
        // answerable by being in front of the monitor.
        FileHandle.standardError.write(
            "canvas \(name): rev \(state.rev) -> \(target?.absoluteString ?? state.url)\n"
                .data(using: .utf8)!)
        // A push is her asking for his eyes: an argument against it would be an
        // argument against the whole channel.
        window.orderFrontRegardless()
    }

    // What the web view is actually showing, as a PNG. The only way to check
    // this app without Screen Recording permission: `screencapture` is refused
    // to an unprivileged process, and a window that cannot be inspected can
    // only be verified by Oscar standing in front of it.
    func snapshot(to path: String, then done: @escaping () -> Void) {
        web.takeSnapshot(with: nil) { image, _ in
            defer { done() }
            guard let tiff = image?.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return }
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: where it sits

    // Per-screen position and size, remembered. He places a widget once.
    private static func savedFrame(_ name: String) -> NSRect {
        if let s = UserDefaults.standard.string(forKey: "frame.\(name)") {
            let r = NSRectFromString(s)
            if r.width > 120 && r.height > 80 { return r }
        }
        let vis = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0,
                                                        width: 1440, height: 900)
        return NSRect(x: vis.maxX - 540, y: vis.maxY - 740,
                      width: 520, height: 700)
    }

    private func remember() {
        UserDefaults.standard.set(NSStringFromRect(window.frame),
                                  forKey: "frame.\(name)")
    }
}

extension Canvas: NSWindowDelegate {
    func windowDidMove(_: Notification) { remember() }
    func windowDidResize(_: Notification) { remember() }
}

// MARK: - run

let app = NSApplication.shared
// .accessory: no Dock icon and no menu bar of its own. These are widgets on his
// desk, not an app he switches to -- but they can still take focus when he
// clicks into one, which .prohibited would refuse.
app.setActivationPolicy(.accessory)

var args = Array(CommandLine.arguments.dropFirst())

// --shot <dir>: draw for a few seconds, write each canvas's page to
// <dir>/<name>.png, quit. A self-check, not a feature.
var shotDir: String?
if let i = args.firstIndex(of: "--shot"), i + 1 < args.count {
    shotDir = args[i + 1]
    args.removeSubrange(i...(i + 1))
}

let names = args.filter {
    !$0.isEmpty && $0.allSatisfy { c in c.isLowercase || c.isNumber || c == "-" }
}
let canvases = (names.isEmpty ? ["desk"] : names).map(Canvas.init)

if let dir = shotDir {
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
        var left = canvases.count
        for c in canvases {
            c.snapshot(to: "\(dir)/\(c.name).png") {
                left -= 1
                if left == 0 { app.terminate(nil) }
            }
        }
    }
}

app.run()
