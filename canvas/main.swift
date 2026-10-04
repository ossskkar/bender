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
// Behind everything, always, is *her* -- the same voice visual the iPad draws,
// compiled from the iPad's own VoiceVisual.swift and Skin.swift rather than
// copied, so the two can never drift into two different faces. A page she puts
// up is an inset panel floating on her, not a replacement for her: when a
// screen is empty the animation is the whole window.
//
//   ./build.sh            # pulls in ../native/Arisu/{VoiceVisual,Skin}.swift
//   ./canvas desk vertical

import Cocoa
import SwiftUI
import WebKit

let BASE = ProcessInfo.processInfo.environment["LAIN_URL"]
    ?? "https://architect-server.tailaa64e9.ts.net:8443"
let POLL = 2.0

// Which of the ten faces. The iPad keeps his pick in its own settings; the desk
// takes the same default (ribbon) and an override, rather than inventing a
// second place for him to choose.
let FACE = FaceStyle(rawValue: ProcessInfo.processInfo.environment["ARISU_FACE"] ?? "")
    ?? .ribbon

// How solid the page card is over her. 1 hides her completely behind it.
let PANEL = Double(ProcessInfo.processInfo.environment["ARISU_PANEL"] ?? "") ?? 0.84

// What lain says a screen is showing. `rev` is the whole point: it moves on
// every push, including a push of the same URL, so "put it up again" works and
// a page he is reading is never reloaded underneath him by a poll that found
// nothing new.
struct ScreenState: Decodable {
    let url: String
    let title: String
    let rev: Int
    /// A big screen holds more than one thing. One panel is the ordinary case
    /// and is what a plain `url` push produces; several are laid out as a grid.
    let panels: [Panel]?
}

struct Panel: Decodable {
    let url: String
    let title: String
}

struct ScreenReply: Decodable {
    let screen: ScreenState?
    let actions: [Action]?
}

/// One thing to do to the page. A fixed verb and a string, never JavaScript
/// from the wire: this window carries his signed-in sessions, and the page she
/// is reading is exactly where an instruction could be planted.
struct Action: Decodable {
    let id: String
    let verb: String
    let arg: String
}

// MARK: - her

// What she is doing, for the animation behind the page.
//
// The honest limit, written down because it is invisible from the outside: her
// real level is never published. `Live.swift` says so in as many words -- it is
// read twenty times a second by whichever device is holding the call and goes
// nowhere else. So the desk reads her *phase* from lain, which is a fact the
// server has, and shapes the level itself. The movement is right; the waveform
// is a stand-in. Publishing the level is a small endpoint and a 20 Hz stream
// from the device in the call, worth doing only if the stand-in reads wrong.
final class Her: ObservableObject {
    @Published var state: VoiceState = .idle
    @Published var amplitude: Double = 0
    /// Whether a page is covering her middle. With one up she is drawn far
    /// larger than the window, so what shows around the panel is her ribbon
    /// moving rather than a dead margin; alone, she is a sphere in the centre.
    @Published var contentUp = false

    private var seq = -1
    private var speakingUntil = Date.distantPast
    private var phase = 0.0

    init() {
        // 20 Hz, the rate the iPad reads her own meter at.
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak self] _ in self?.breathe()
        }
        poll()
    }

    // Her state is a long poll: the server holds the request open until she
    // says something, so this is one idle connection rather than a request
    // every two seconds, and a line reaches the desk the moment it exists.
    private func poll() {
        guard let url = URL(string: "\(BASE)/arisu/state?wait=1&since=\(seq)")
        else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 40
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self else { return }
            defer {
                // Always poll again, and never in a tight loop when the server
                // is down -- a canvas on a sleeping laptop would otherwise spin.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.poll() }
            }
            guard let data,
                  let got = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else { return }
            DispatchQueue.main.async { self.heard(got) }
        }.resume()
    }

    private func heard(_ got: [String: Any]) {
        let n = (got["seq"] as? Int) ?? -1
        defer { seq = max(seq, n) }
        guard n > seq, let line = got["line"] as? String, !line.isEmpty else { return }
        // How long she will be talking. Nothing reports the end of a line, so
        // it is estimated from its length -- roughly 14 characters a second,
        // which is ordinary speech -- and a floor so a two-word answer still
        // registers as her having spoken.
        speakingUntil = Date().addingTimeInterval(
            max(1.6, Double(line.count) / 14))
        state = .speaking
    }

    private func breathe() {
        if state == .speaking && Date() >= speakingUntil { state = .idle }
        phase += 0.05
        // A stand-in for her voice: two detuned waves, so it swells and dips
        // like speech instead of pulsing like a metronome.
        let v = 0.5 + 0.28 * sin(phase * 5.3) + 0.18 * sin(phase * 11.7)
        let target = state == .speaking ? max(0.08, min(1, v)) : 0.0
        amplitude += (target - amplitude) * 0.25
    }

    var tint: Color {
        // The same four hues the iPad wears, so one glance means the same
        // thing on either screen: indigo waiting, green hearing him, magenta
        // working, cyan talking.
        switch state {
        case .idle:      return Color(red: 0.50, green: 0.55, blue: 1.0)
        case .listening: return Color(red: 0.30, green: 1.0, blue: 0.50)
        case .thinking:  return Color(red: 1.0, green: 0.22, blue: 0.78)
        case .speaking:  return Color(red: 0.27, green: 0.90, blue: 0.97)
        }
    }
}

// The window's floor: her, at full size, always. The page is a card centred on
// her, smaller than the window and slightly see-through, so she is visible
// around it and faintly through it (Oscar, 2026-10-04 -- this replaced an
// earlier band across the top, which kept her visible by giving her a strip of
// her own rather than by actually being behind anything).
struct Backdrop: View {
    @ObservedObject var her: Her
    let style: FaceStyle

    var body: some View {
        ZStack {
            Skin.void
            VoiceVisual(style: style, state: her.state,
                        amplitude: her.amplitude, tint: her.tint,
                        // Larger with a page up, so her ribbon runs past the
                        // card's edges instead of hiding entirely under it.
                        scale: her.contentUp ? 1.45 : 0.8, bloom: 1, speed: 1)
        }
        .ignoresSafeArea()
    }
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

    /// Where it was before it filled the screen.
    private var restore: NSRect?

    // Escape puts it away. With no title bar there is no close button, and a
    // widget he cannot dismiss is one he ends up quitting the whole app to be
    // rid of. It comes back by itself the next time she pushes to this name.
    //
    // ⌘⏎ fills the screen it is on and ⌘⏎ again puts it back. Not the green
    // button (there is no title bar) and not real macOS full screen, which
    // would give it a Space of its own -- the point of these windows is that
    // they are on top of whatever he is doing, which a Space would end.
    override func keyDown(with event: NSEvent) {
        switch (event.keyCode, event.modifierFlags.contains(.command)) {
        case (53, _):      orderOut(nil)
        case (36, true):   fill()
        default:           super.keyDown(with: event)
        }
    }

    /// Fill a screen, or go back to the size it was. `display` picks a
    /// monitor by index (0 is the main one) -- the vertical monitor is the
    /// whole point of a window she can send somewhere.
    @discardableResult
    func fill(display: Int = -1) -> String {
        if display < 0, let was = restore {
            restore = nil
            setFrame(was, display: true, animate: true)
            return "back to its own size"
        }
        let screens = NSScreen.screens
        let target = display >= 0 && display < screens.count
            ? screens[display]
            : (screen ?? NSScreen.main)
        guard let vis = target?.visibleFrame else { return "no screen to fill" }
        if restore == nil { restore = frame }
        setFrame(vis, display: true, animate: true)
        return screens.count > 1
            ? "filling screen \(screens.firstIndex(of: target!) ?? 0) of \(screens.count)"
            : "filling the screen"
    }
}

// MARK: - a canvas

final class Pane: NSObject, WKNavigationDelegate {
    let name: String
    let window: Frameless
    /// One web view per panel. A screen usually holds one; a big screen holds
    /// several, which is the whole reason this is a list.
    private var webs: [WKWebView] = []
    private let conf: WKWebViewConfiguration
    private let grid = NSStackView()
    private var rev = -1
    private let her = Her()
    private var timer: Timer?

    init(name: String) {
        self.name = name

        let conf = WKWebViewConfiguration()
        // Every page paints its own ground -- lain's is near-black, Google's is
        // white -- and that ground is what hides her. Taking it away leaves the
        // page's text and its own cards drawing over the translucent card
        // below, which is the only way to have her visible AND the page
        // readable at the same time.
        conf.userContentController.addUserScript(WKUserScript(
            source: """
            (function () {
              var s = document.createElement('style');
              s.textContent = 'html,body{background:transparent !important;' +
                'background-color:transparent !important;' +
                'background-image:none !important}';
              (document.head || document.documentElement).appendChild(s);
            })();
            """,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        self.conf = conf

        window = Frameless(contentRect: Pane.savedFrame(name),
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
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true

        // Her, behind everything and always running. The page is a panel that
        // floats on her: inset so she shows around it, and taken away entirely
        // when the screen is empty, so an idle canvas is just her face.
        let backdrop = NSHostingView(rootView: Backdrop(her: her, style: FACE))

        let grab = Grab()
        grid.orientation = .vertical
        grid.distribution = .fillEqually
        grid.spacing = 10

        for v in [root, backdrop, grid, grab] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        root.addSubview(backdrop)
        root.addSubview(grid)
        root.addSubview(grab)                  // over both, invisible
        window.contentView = root

        // The pages float *on* her rather than replacing her (Oscar): she fills
        // the window, they sit in a grid centred on it, and each is slightly
        // see-through so her ribbon moves behind them as well as around them.
        // 86% of each side leaves a real margin at any window size, which a
        // fixed inset does not.
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: root.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            grid.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            grid.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.86),
            grid.heightAnchor.constraint(equalTo: root.heightAnchor, multiplier: 0.86),

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

    // An empty screen is her face filling the window. There is no "waiting"
    // card any more: the animation already says the canvas is alive, and a
    // label saying so as well is one more thing on the desk to read.
    private func idle() {
        her.contentUp = false
        webs = []
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        grid.isHidden = true
    }

    /// Build the grid for `panels`. Rows and columns are chosen so the cells
    /// stay as square as the window allows: one fills it, two sit side by side,
    /// three or four make a square, five or six a 3x2.
    private func build(_ panels: [Panel]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        webs = []
        let cols = panels.count <= 1 ? 1 : (panels.count <= 4 ? 2 : 3)
        var row: NSStackView?
        for (i, _) in panels.enumerated() {
            if i % cols == 0 {
                let r = NSStackView()
                r.orientation = .horizontal
                r.distribution = .fillEqually
                r.spacing = 10
                grid.addArrangedSubview(r)
                row = r
            }
            // Each panel is a card of its own: rounded, translucent, with the
            // page drawn edge to edge inside it. The page's own background was
            // stripped on load, so what shows through the text is her.
            let card = NSView()
            card.wantsLayer = true
            card.layer?.cornerRadius = 14
            card.layer?.masksToBounds = true
            card.layer?.backgroundColor = NSColor(red: 0.02, green: 0.02,
                                                  blue: 0.05, alpha: PANEL).cgColor
            let w = WKWebView(frame: .zero, configuration: conf)
            // Transparent so a page with no background of its own lets her
            // through. Private API by name only; it has been this key since
            // 2014 and the failure mode if it ever goes is an opaque panel.
            w.setValue(false, forKey: "drawsBackground")
            if #available(macOS 12.0, *) { w.underPageBackgroundColor = .clear }
            w.navigationDelegate = self
            w.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(w)
            NSLayoutConstraint.activate([
                w.topAnchor.constraint(equalTo: card.topAnchor),
                w.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                w.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                w.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            ])
            webs.append(w)
            row?.addArrangedSubview(card)
        }
        grid.isHidden = false
        her.contentUp = true
    }

    private func fetch() {
        guard let url = URL(string: "\(BASE)/screens?name=\(name)&take=1")
        else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let reply = try? JSONDecoder().decode(ScreenReply.self,
                                                        from: data)
            else { return }
            DispatchQueue.main.async {
                self.apply(reply.screen)
                for a in reply.actions ?? [] { self.perform(a) }
            }
        }.resume()
    }

    private func apply(_ state: ScreenState?) {
        guard let state else {
            // Cleared. Back to her face rather than the last page, so a blanked
            // screen does not keep claiming yesterday is current.
            if rev != -1 {
                rev = -1
                idle()
            }
            return
        }
        guard state.rev != rev else { return }
        rev = state.rev
        let panels = state.panels ?? [Panel(url: state.url, title: state.title)]
        window.title = state.title.isEmpty ? state.url : state.title
        build(panels)
        for (i, panel) in panels.enumerated() where i < webs.count {
            load(panel.url, into: webs[i])
        }
        FileHandle.standardError.write(
            "canvas \(name): rev \(state.rev) -> \(panels.map { $0.url }.joined(separator: " | "))\n"
                .data(using: .utf8)!)
        // A push is her asking for his eyes: an argument against it would be an
        // argument against the whole channel.
        window.orderFrontRegardless()
    }

    /// Three kinds of thing she can put up, in the order they are tried: a file
    /// on this Mac (a PDF, an image, anything WebKit renders -- which needs
    /// loadFileURL and a read grant, not a plain request), an absolute URL, and
    /// otherwise a path resolved against lain.
    private func load(_ url: String, into web: WKWebView) {
        if url.hasPrefix("/"), FileManager.default.fileExists(atPath: url) {
            let f = URL(fileURLWithPath: url)
            web.loadFileURL(f, allowingReadAccessTo: f.deletingLastPathComponent())
        } else if let u = URL(string: url), u.scheme == "file" {
            web.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent())
        } else if let target = URL(string: url, relativeTo: URL(string: BASE)) {
            web.load(URLRequest(url: target))
        }
    }

    // MARK: being driven

    private func perform(_ a: Action) {
        FileHandle.standardError.write(
            "canvas \(name): \(a.verb) \(a.arg)\n".data(using: .utf8)!)
        // Every verb answers. The first version let only `read` and `click`
        // report, so a scroll that worked perfectly came back to her as "the
        // window did not answer" -- she would have told him it had failed.
        let page = 0.85                 // a "page" of scrolling is most of one
        let web = panel(a.arg)
        switch a.verb {
        case "back":    web?.goBack();    note("went back")
        case "forward": web?.goForward(); note("went forward")
        case "reload":  web?.reload();    note("reloaded the page")
        case "top":     scrolling("0", on: web)
        case "bottom":  scrolling("max", on: web)
        case "up":      scrolling("scrollY - innerHeight * \(page)", on: web)
        case "down":    scrolling("scrollY + innerHeight * \(page)", on: web)
        case "fill":    note(window.fill(display: Int(a.arg) ?? -1))
        case "restore": note(window.fill())
        case "find":    hunt(a.arg, click: false)
        case "click":   hunt(a.arg, click: true)
        case "read":    readBack()
        default:        note("I do not know how to \(a.verb)")
        }
    }

    /// Which panel a verb acts on. A leading number picks one, counting from
    /// 1 the way he would say it ("scroll the second one down"); anything else
    /// means the first, which is the only one when there is only one.
    private func panel(_ arg: String) -> WKWebView? {
        if let n = Int(arg.prefix(while: \.isNumber)), n >= 1, n <= webs.count {
            return webs[n - 1]
        }
        return webs.first
    }

    /// Scroll to `target` and say where on the page that is -- "nothing
    /// happened" and "already at the bottom" are different answers, and she
    /// needs the second one to stop asking for more.
    ///
    /// The position is worked out *before* the scroll, not after: the scroll is
    /// smooth, so reading `scrollY` afterwards reads it mid-flight, and
    /// `evaluateJavaScript` hands back nil for a Promise rather than waiting
    /// for one -- which is how the first version came back saying only
    /// "scrolled" every time.
    private func scrolling(_ target: String, on web: WKWebView?) {
        guard let web else { return note("nothing is up on that screen") }
        js("""
        (function () {
          var max = Math.max(0, document.body.scrollHeight - innerHeight);
          if (max <= 0) return 'the whole page already fits';
          var to = Math.min(max, Math.max(0, \(target)));
          window.scrollTo({ top: to, behavior: 'smooth' });
          var pct = Math.round(100 * to / max);
          if (pct <= 0) return 'at the top of the page';
          if (pct >= 100) return 'at the bottom of the page';
          return pct + '% down the page';
        })();
        """, on: web) { self.note(($0 as? String) ?? "scrolled") }
    }

    private func note(_ line: String) {
        send(["name": name, "text": line])
    }

    private func js(_ source: String, on web: WKWebView?,
                    then: ((Any?) -> Void)? = nil) {
        guard let web else { then?(nil); return }
        web.evaluateJavaScript(source) { got, _ in then?(got) }
    }

    /// Find the thing on the page he named and either scroll to it or click it.
    /// Matching is on visible text, because that is the only handle he has --
    /// he says "click sign in", not "click the third button".
    ///
    /// Every panel is searched, not just the first: on a big screen he is
    /// looking at the grid, not at one of them, and asking him which panel the
    /// link is in would be asking him to do the looking.
    private func hunt(_ what: String, click: Bool) {
        guard let needle = try? String(data: JSONEncoder().encode(what),
                                       encoding: .utf8) ?? "\"\"" else { return }
        let source = """
        (function (want, click) {
          want = want.toLowerCase().trim();
          if (!want) return '';
          var sel = click
            ? 'a,button,[role=button],input[type=submit],input[type=button],summary'
            : '*';
          var best = null;
          var all = document.querySelectorAll(sel);
          for (var i = 0; i < all.length; i++) {
            var el = all[i];
            var t = (el.innerText || el.value || el.getAttribute('aria-label') || '');
            t = t.toLowerCase().trim();
            if (!t || t.indexOf(want) < 0) continue;
            // Skipping every element with children was too strict: a heading
            // wrapping a link has children, and that is exactly the heading he
            // asked to scroll to. Shortest match below picks the inner one.
            if (!best || t.length < best.t.length) best = { el: el, t: t };
          }
          if (!best) return '';
          best.el.scrollIntoView({ block: 'center', behavior: 'smooth' });
          if (click) best.el.click();
          return (click ? 'clicked: ' : 'found: ') + best.t.slice(0, 80);
        })(\(needle), \(click));
        """
        search(source, from: 0, what: what)
    }

    /// Try each panel in turn and report the first that matched. Sequential
    /// rather than all at once because a click is not a thing to do twice.
    private func search(_ source: String, from i: Int, what: String) {
        guard i < webs.count else {
            note("no match for: \(what)")
            return
        }
        js(source, on: webs[i]) { got in
            let answer = (got as? String) ?? ""
            if answer.isEmpty {
                self.search(source, from: i + 1, what: what)
            } else {
                self.note(self.webs.count > 1
                          ? "\(answer) (panel \(i + 1))" : answer)
            }
        }
    }

    /// What the pages say, in her direction. Text and not HTML: she is reading
    /// it, and the markup is thousands of tokens of nothing.
    ///
    /// The article rather than the document when a page offers one. Every read
    /// of a Wikipedia page used to open with "Jump to content / Main menu /
    /// Search / Appearance / Personal tools" -- navigation furniture that is a
    /// fifth of a short page, says nothing, and is re-sent on every turn she
    /// takes afterwards.
    private func readBack() {
        let source = """
        (function () {
          var el = document.querySelector('article, main, [role=main]')
                || document.body;
          var t = (el.innerText || '');
          return t.replace(/[ \\t]+\\n/g, '\\n').replace(/\\n{3,}/g, '\\n\\n').trim();
        })();
        """
        gather(source, from: 0, into: [])
    }

    private func gather(_ source: String, from i: Int, into parts: [String]) {
        guard i < webs.count else {
            send(["name": name, "text": parts.joined(separator: "\n\n")])
            return
        }
        js(source, on: webs[i]) { got in
            let text = (got as? String) ?? ""
            let head = self.webs.count > 1 ? "--- panel \(i + 1) ---\n" : ""
            self.gather(source, from: i + 1, into: parts + [head + text])
        }
    }

    /// Note where this screen landed: the address, the title, and a sentence of
    /// what the page is about. Sent on its own, not as part of a read, because
    /// this is the part that is *kept* -- the page's text goes when the page
    /// does, and this is what she still has afterwards (Oscar, 2026-10-05).
    private func noteVisit(_ web: WKWebView) {
        js("""
        (function () {
          var meta = document.querySelector('meta[name="description"]')
                  || document.querySelector('meta[property="og:description"]');
          var gist = meta ? (meta.content || '') : '';
          if (!gist) {
            var el = document.querySelector('article, main, [role=main]')
                  || document.body;
            gist = (el.innerText || '').replace(/\\s+/g, ' ').trim();
          }
          return JSON.stringify({
            url: location.href,
            title: (document.title || '').slice(0, 120),
            gist: gist.slice(0, 240)
          });
        })();
        """, on: web) { got in
            guard let raw = got as? String,
                  let data = raw.data(using: .utf8),
                  let v = try? JSONSerialization.jsonObject(with: data)
                    as? [String: String]
            else { return }
            self.sendAny(["name": self.name, "visit": v])
        }
    }

    private func sendAny(_ body: [String: Any]) {
        guard let url = URL(string: "\(BASE)/screens"),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req).resume()
    }

    private func send(_ body: [String: String]) {
        sendAny(body)
    }

    /// The window as it looks, as a PNG. The only way to check this app without
    /// Screen Recording permission: `screencapture` is refused to an
    /// unprivileged process, and a window that cannot be inspected can only be
    /// verified by Oscar standing in front of it.
    ///
    /// Two captures composed, because neither tool sees the whole window:
    /// cacheDisplay draws the AppKit and SwiftUI layers but not the web views,
    /// which render in their own process, and takeSnapshot draws only a page.
    func snapshot(to path: String, then done: @escaping () -> Void) {
        shoot(from: 0, into: [:]) { pages in
            defer { done() }
            guard let root = self.window.contentView,
                  let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)
            else { return }
            root.cacheDisplay(in: root.bounds, to: rep)
            let shot = NSImage(size: root.bounds.size)
            shot.lockFocus()
            rep.draw(in: root.bounds)
            for (i, page) in pages where i < self.webs.count {
                let w = self.webs[i]
                page.draw(in: w.convert(w.bounds, to: root))
            }
            shot.unlockFocus()
            guard let tiff = shot.tiffRepresentation,
                  let out = NSBitmapImageRep(data: tiff),
                  let png = out.representation(using: .png, properties: [:])
            else { return }
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    private func shoot(from i: Int, into got: [Int: NSImage],
                       then: @escaping ([Int: NSImage]) -> Void) {
        guard i < webs.count else { return then(got) }
        webs[i].takeSnapshot(with: nil) { image, _ in
            var next = got
            if let image { next[i] = image }
            self.shoot(from: i + 1, into: next, then: then)
        }
    }

    // MARK: where it sits
    // MARK: where it sits

    // Per-screen position and size, remembered. He places a widget once.
    private static func savedFrame(_ name: String) -> NSRect {
        if let s = UserDefaults.standard.string(forKey: "frame.\(name)"),
           Self.usable(NSRectFromString(s)) {
            return NSRectFromString(s)
        }
        let vis = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0,
                                                        width: 1440, height: 900)
        return NSRect(x: vis.maxX - 540, y: vis.maxY - 740,
                      width: 520, height: 700)
    }

    private func remember() {
        // Only a frame worth coming back to. AppKit resizes a window to zero
        // while it is being torn down, and that arrived here as a saved
        // 0x0 at the old origin -- the next launch then opened a window with
        // no size at all, on a monitor that may not be plugged in.
        guard Pane.usable(window.frame) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame),
                                  forKey: "frame.\(name)")
    }

    /// Big enough to see and somewhere a screen actually is.
    private static func usable(_ r: NSRect) -> Bool {
        guard r.width > 160, r.height > 120 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(r) }
    }
}

extension Pane {
    /// Every page that finishes loading, not only the ones she pushed: a page
    /// he reached by asking her to click a link is exactly the one he will ask
    /// about later.
    func webView(_ web: WKWebView, didFinish _: WKNavigation!) {
        // The idle page is not somewhere he has been.
        guard web.url?.absoluteString != "about:blank" else { return }
        noteVisit(web)
    }
}

extension Pane: NSWindowDelegate {
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
let canvases = (names.isEmpty ? ["desk"] : names).map(Pane.init)

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
