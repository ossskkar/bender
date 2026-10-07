import SwiftUI
import UIKit
import CoreText

/// The versions of the iPad app (Oscar, 2026-10-01). Classic is the screen
/// with the deck, the record panel and the chat; Singularity is the whole
/// screen given to her, the deck falling into her eye. Sigil and Clockwork
/// were built and dropped the same day: Singularity is the one he kept.
/// A three-finger swipe flips between them; the title's menu picks one.
enum Look: String, CaseIterable, Identifiable {
    case classic, singularity
    static let key = "arisu.look"
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }

    func step(_ by: Int) -> Look {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + by + all.count) % all.count]
    }
}

/// Three fingers, left or right, anywhere on the window. Not four: iPadOS
/// takes four-finger swipes for switching apps (Oscar, 2026-10-01). Three is
/// undo and redo while typing, which these screens never are.
struct ThreeFingerSwipe: UIViewRepresentable {
    let onSwipe: (Int) -> Void

    func makeUIView(context: Context) -> Host { Host(onSwipe: onSwipe) }
    func updateUIView(_ v: Host, context: Context) { v.onSwipe = onSwipe }

    final class Host: UIView, UIGestureRecognizerDelegate {
        var onSwipe: (Int) -> Void
        private let left = UISwipeGestureRecognizer(), right = UISwipeGestureRecognizer()

        init(onSwipe: @escaping (Int) -> Void) {
            self.onSwipe = onSwipe
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            for (g, dir) in [(left, UISwipeGestureRecognizer.Direction.left), (right, .right)] {
                g.direction = dir
                g.numberOfTouchesRequired = 3
                g.cancelsTouchesInView = false
                g.delegate = self
                g.addTarget(self, action: #selector(fire(_:)))
            }
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            for g in [left, right] { g.view?.removeGestureRecognizer(g); window?.addGestureRecognizer(g) }
        }

        @objc private func fire(_ g: UISwipeGestureRecognizer) { onSwipe(g.direction == .left ? 1 : -1) }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - The screen

/// Everything that changes frame to frame and is not worth a SwiftUI update:
/// the smoothed level, the ripples, her arrival, where each tappable thing was
/// last drawn.
private final class RealmClock {
    #if DEBUG
    /// Frames a second into the simulator's log every five seconds, for
    /// measuring the screen's cost: `simctl launch … -arisu.fps YES` (23.0).
    static let logFPS = UserDefaults.standard.bool(forKey: "arisu.fps")
    private var frames = 0, since = Date()
    func countFrame() {
        guard Self.logFPS else { return }
        frames += 1
        let d = Date().timeIntervalSince(since)
        if d >= 5 { NSLog("arisu fps %.1f", Double(frames) / d); frames = 0; since = Date() }
    }
    #endif
    let start = Date()
    var last = 0.0
    var tw = 0.0
    var amp = 0.0
    var energy = 0.0
    var lastAmp = 0.0
    var waves: [(t0: Double, s: Double)] = []
    /// The Mac's music while she is away (Oscar, 2026-10-02: "more explosive,
    /// more shockwaves and space warping, and colour"): `groove` is its
    /// smoothed level, which bends and twists space; every beat is a `boom`,
    /// a ring of light of its own; `hue` turns the colours with it and
    /// settles back to her cyan when the music stops.
    var groove = 0.0
    var lastMusic = 0.0
    var lastBoom = 0.0
    var hue = 0.0
    var booms: [(t0: Double, s: Double, hue: Double)] = []
    var glitchUntil = 0.0
    var summonAt: Double?
    var dismissAt: Double?
    var banged = false
    /// The chant burning on the screen: when it struck, and what it says.
    /// Runes, because Old Norse in Latin letters is a transliteration of a
    /// transliteration (Oscar, 2026-10-03).
    var chantAt: Double?
    var chant = ""
    /// The same line in Latin letters, small, under the runes.
    var chantLatin = ""
    /// A ring he tapped, and when: it swells and turns readable for a moment
    /// rather than opening a panel (Oscar, 2026-10-03).
    var openRing: Int?
    var openAt = 0.0
    /// Where the information rings were drawn this frame: the index, the
    /// radius, and the squash. The tap reads these rather than recomputing
    /// them -- two copies of the same geometry is how every ring tap went
    /// missing (Oscar, 2026-10-03).
    var rings: [(k: Int, r: Double, ax: Double, ay: Double)] = []
    /// Her name drifting back now and then: when, where (as a share of the
    /// screen) and how big.
    var echo: (t0: Double, x: Double, y: Double, size: Double)?
    /// The shake and zoom the last frame was drawn with, to map a tap back.
    var offset = CGSize.zero
    var zoom = 1.0
    var size = CGSize.zero
    var hits: [(at: CGPoint, r: Double, tap: Tap)] = []
    /// Every piece of text already laid out, by text, size, weight and colour.
    /// Laying out each letter of the rings afresh 60 times a second was most
    /// of the screen's cost: a whole core with nothing happening (19.0).
    // ponytail: cleared wholesale when it passes 3000; an LRU if her lines churn.
    var laid: [Ink: GraphicsContext.ResolvedText] = [:]
    struct Ink: Hashable { let s: String, size: Double, weight: Font.Weight, col: Color }
    /// The outline of each letter the rings use, centred on the origin as
    /// `Text` drawn at a point would be, in the same monospaced system font.
    var letters: [String: Path] = [:]

    func letter(_ ch: Character, _ size: Double) -> Path {
        let key = "\(ch)\u{1}\(size)"
        if let p = letters[key] { return p }
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
        let str = String(ch) as CFString
        // A letter SF Mono lacks (∴, kana) comes from the font iOS falls back to.
        let font = CTFontCreateForString(base, str, CFRange(location: 0, length: CFStringGetLength(str)))
        var units = Array(String(ch).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count)
        var path = Path()
        if let g = glyphs.first, g != 0 {
            var adv = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, [g], &adv, 1)
            let mid = (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
            if let cg = CTFontCreatePathForGlyph(font, g, nil) {
                // Glyphs are drawn y-up; the canvas is y-down.
                path = Path(cg).applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -adv.width / 2, ty: mid))
            }
        }
        if letters.count > 3000 { letters.removeAll() }
        letters[key] = path
        return path
    }

    /// A whole label as one shape, letters side by side and centred on the
    /// origin, as `Text` drawn at a point would be. Made once per label.
    var words: [String: Path] = [:]

    func word(_ s: String, _ size: Double) -> Path {
        let key = "\(s)\u{1}\(size)"
        if let p = words[key] { return p }
        let step = size * 0.62
        var path = Path()
        for (i, ch) in s.enumerated() {
            let x = (Double(i) - Double(s.count - 1) / 2) * step
            path.addPath(letter(ch, size), transform: CGAffineTransform(translationX: x, y: 0))
        }
        if words.count > 500 { words.removeAll() }
        words[key] = path
        return path
    }

    enum Tap { case app(String), button(DeckButton), her, ring(Int) }

    var now: Double { Date().timeIntervalSince(start) }
}

/// Old Norse in the letters it was carved in. Elder Futhark has no c, q, w, x
/// or z, and one rune does both i and j; anything unmapped is dropped rather
/// than drawn as a Latin letter in the middle of a line of runes
/// (Oscar, 2026-10-03: "written using runas writing").
enum Runes {
    private static let map: [Character: String] = [
        "a": "ᚨ", "á": "ᚨ", "b": "ᛒ", "c": "ᚲ", "d": "ᛞ", "e": "ᛖ", "é": "ᛖ",
        "f": "ᚠ", "g": "ᚷ", "h": "ᚺ", "i": "ᛁ", "í": "ᛁ", "j": "ᛁ", "k": "ᚲ",
        "l": "ᛚ", "m": "ᛗ", "n": "ᚾ", "o": "ᛟ", "ó": "ᛟ", "p": "ᛈ", "r": "ᚱ",
        "s": "ᛋ", "t": "ᛏ", "u": "ᚢ", "ú": "ᚢ", "v": "ᚹ", "w": "ᚹ", "y": "ᚤ",
        "ý": "ᚤ", "þ": "ᚦ", "ð": "ᚦ", "æ": "ᚨ", "ö": "ᛟ", "ø": "ᛟ", "x": "ᚲᛋ",
        "z": "ᛉ", "q": "ᚲ",   // x is two runes; the rest are one
    ]

    static func carve(_ line: String) -> String {
        var out = ""
        for ch in line.lowercased() {
            if let r = map[ch] { out += r }
            else if ch == " " { out.append("᛬") }          // the word divider
            else if ch == "," || ch == "." { continue }
        }
        return out
    }
}

/// Singularity (Oscar, 2026-10-01): her eye is a black hole, every app of the
/// deck a spiral arm of its actions falling in. A long press anywhere summons
/// her -- the screen is sucked into the eye, goes dark, and she arrives in a
/// flash and a shockwave -- and while she speaks, all of it moves with her.
struct RealmView: View {
    /// Her own level, before the Mac's music is mixed in.
    let level: Double
    let idle: Bool
    let speaking: Bool
    let running: Bool
    let tint: Color
    let status: String
    let micOn: Bool
    let onHer: () -> Void
    let onSummon: () -> Void
    /// A double tap starts or ends the conversation. Entering Singularity
    /// plays her arrival either way: he wanted the room alive the moment he
    /// walks in, and her listening only when he asks (Oscar, 2026-10-03).
    var onTalk: () -> Void = {}
    /// The line she will speak, so it can be carved while she says it.
    var chant: String = ""
    /// A demo's track instead of the Mac's: a beat every half second, louder
    /// and softer over a few seconds, made here and heard by nobody (21.0).
    var fakeMusic = false
    /// lain's day, read once for the whole app: Singularity used to keep a
    /// second reader of the same data.json (22.0).
    @ObservedObject var info: LainInfo
    /// Night hours: she is not listening, and the screen draws half as often.
    var night = false

    @StateObject private var deck = Deck()
    @StateObject private var music = MacMusic()
    @State private var clock = RealmClock()
    @State private var chosen = ""
    @State private var pressed: (label: String, id: String, t: Double)?

    var body: some View {
        // Thirty frames a second while she is away: space only drifts then, and
        // sixty cost twice the battery for nothing he could see (19.0). Fifteen
        // at night, when nobody is watching it drift (22.0).
        TimelineView(.animation(minimumInterval: running ? nil : 1.0 / (night ? 15 : 30))) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(clock.start)
                step(t)
                #if DEBUG
                clock.countFrame()
                #endif
                clock.size = size
                let stage = stage(t)
                clock.hits = []
                clock.rings = []
                // Only her arrival shakes the frame; her speech bends space and
                // nothing else (Oscar, 2026-10-01).
                let shake = stage.shake
                clock.offset = CGSize(width: Double.random(in: -1...1) * shake,
                                      height: Double.random(in: -1...1) * shake)
                clock.zoom = 1
                var c = ctx
                c.translateBy(x: size.width / 2 + clock.offset.width, y: size.height / 2 + clock.offset.height)
                c.scaleBy(x: clock.zoom, y: clock.zoom)
                c.translateBy(x: -size.width / 2, y: -size.height / 2)
                draw(c, size, t, stage)
                if t < clock.glitchUntil { glitch(c, size, t, stage) }
                overlay(ctx, size, stage)
                scanlines(ctx, size)
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        // Three gestures, and the order matters: chaining them with
        // `exclusively` left the single tap waiting on the double tap forever,
        // so nothing in the realm answered a touch (Oscar, 2026-10-03).
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onSummon() })
        .onTapGesture(count: 2) { onTalk() }
        .gesture(SpatialTapGesture().onEnded { tap($0.location) })
        .ignoresSafeArea()
        .task { await deck.load() }
        .task { await deck.watchFront() }
        .task(id: idle) { if idle { await music.listen() } }
        .onChange(of: deck.front) { _, g in if !g.isEmpty { chosen = g } }
        .onAppear {
            // Walking in is an arrival: the gather, the dark, the flash and
            // the shockwave play now, with no call behind them.
            clock.summonAt = clock.now
            clock.dismissAt = nil
            clock.banged = false
        }
        .onChange(of: chant) { _, line in
            guard !line.isEmpty else { return }
            clock.chant = Runes.carve(line)
            clock.chantLatin = line
            // It strikes as she arrives, not while the screen is still being
            // pulled into the dark (gather is 2 s).
            clock.chantAt = clock.now + Self.gather + 0.5
        }
        .onChange(of: running) { _, on in
            // Her arrival is not replayed if the room is still ringing from
            // the one he just walked into.
            let fresh = clock.summonAt.map { clock.now - $0 > 6 } ?? true
            if on {
                if fresh { clock.summonAt = clock.now; clock.banged = false }
                clock.dismissAt = nil
            }
            else { clock.dismissAt = clock.now; clock.summonAt = nil }
        }
    }

    /// How long she gathers before she arrives; `sound/awaken.py` BANG matches.
    static let gather = 2.0

    /// Advance what carries over from frame to frame. Once per frame, never
    /// from the glitch's redraws.
    private func step(_ t: Double) {
        let dt = min(0.05, max(0, t - clock.last))
        clock.last = t
        let heard = fakeMusic ? 0.2 + 0.65 * exp(-frac(t * 2) * 7) * (0.75 + 0.25 * sin(t * 0.9)) : music.level
        let target = idle ? max(level, heard) : level
        clock.amp += (target - clock.amp) * 0.25
        clock.energy += ((speaking ? clock.amp : 0) - clock.energy) * 0.3
        clock.tw += dt * (running ? 1 : 0.5)
        // A syllable or a beat sends a ripple through space; hers are bigger.
        if clock.amp - clock.lastAmp > (speaking ? 0.045 : 0.18) {
            // Her voice throws real waves now: "more dramatic and strong"
            // (Oscar, 2026-10-03). The arrival is still the biggest thing
            // that happens here, at 5.
            clock.waves.append((t, speaking ? 1.1 + clock.amp * 2.2 : 0.6 + clock.amp))
        }
        clock.lastAmp = clock.amp
        let m = idle ? heard : 0
        clock.groove += (m - clock.groove) * 0.2
        clock.hue += dt * clock.groove * 0.25
        if m - clock.lastMusic > 0.08, t - clock.lastBoom > 0.12 {
            let strength = 0.8 + m * 2.5
            clock.waves.append((t, strength))
            clock.booms.append((t, strength, clock.hue))
            clock.hue += 0.06 + m * 0.1
            clock.lastBoom = t
        }
        clock.lastMusic = m
        if clock.groove < 0.03 {   // silence: back to her own colour
            clock.hue += (clock.hue.rounded() - clock.hue) * min(1, dt * 0.8)
        }
        clock.booms.removeAll { t - $0.t0 > 1.6 }
        if clock.booms.count > 6 { clock.booms.removeFirst(clock.booms.count - 6) }
        clock.waves.removeAll { t - $0.t0 > 3 }
        if Double.random(in: 0...1) < 0.003 { clock.glitchUntil = t + 0.12 }
        // アリス, back at a random moment and place, about once a minute
        // (Oscar, 2026-10-02). Not while she is arriving: that one is hers.
        if let e = clock.echo, t - e.t0 > 3 { clock.echo = nil }
        if clock.echo == nil, clock.summonAt.map({ t - $0 > 8 }) ?? true,
           Double.random(in: 0...1) < dt / 60 {
            clock.echo = (t, Double.random(in: 0.2...0.8), Double.random(in: 0.2...0.8),
                          Double.random(in: 0.08...0.2))
        }
        // The moment she arrives.
        if let s = clock.summonAt, t - s >= Self.gather, !clock.banged {
            clock.banged = true
            clock.waves.append((t, 5))
            clock.glitchUntil = t + 0.35
        }
    }

    /// Her arrival: pulled into the eye and dark for a second, then a flash, a
    /// shockwave and everything thrown back out past where it was. Her leaving:
    /// a shudder inward and the eye closing to a slit.
    private func stage(_ t: Double) -> Stage {
        func ease(_ x: Double) -> Double { let u = min(1, max(0, x)); return u * u * (3 - 2 * u) }
        var s = Stage()
        if let a = clock.summonAt, t - a < Self.gather + 4.5 {
            let k = t - a
            if k < Self.gather {
                let p = ease(k / Self.gather)
                s.rf = 1 - 0.7 * p
                s.eye = 1 - 0.8 * p
                s.dim = 0.72 + 0.28 * p
                s.dark = 0.8 * p
                s.presence = 0.5 + 0.2 * p
                s.shake = 4 * p
            } else {
                // A slower settle: the spring rings longer, the flash lingers,
                // her name holds the screen for four seconds (Oscar, 2026-10-02).
                let u = k - Self.gather
                s.rf = 1 + 0.3 * exp(-u * 1.4) * cos(u * 6)
                s.eye = 1 + 0.7 * exp(-u * 1.2)
                s.flash = max(0, 1 - u / 1.0)
                s.kana = sin(min(1, u / 4.0) * .pi) * 0.7
                s.shake = 24 * exp(-u * 2.5)
            }
        }
        // The chant burns for a second and fades for six, over whatever else
        // is happening (Oscar, 2026-10-03).
        if let c = clock.chantAt {
            let k = t - c
            if k < 9 {
                // Struck, held at full for a second and a half, then eight
                // seconds of cooling.
                s.chant = k < 1.5 ? 1 : max(0, 1 - (k - 1.5) / 7.5)
                s.chantHeat = max(0, 1 - k / 0.8)
            }
        }
        if let d = clock.dismissAt, t - d < 1.4 {
            let p = ease((t - d) / 1.4)
            s.rf = 1 - 0.25 * sin(p * .pi)
            s.dim = 0.72 * p
            s.presence = 1 - 0.5 * p
            s.shake = 3 * (1 - p)
        } else if !running {
            s.dim = 0.72
            s.presence = 0.5
        }
        return s
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ stage: Stage) {
        let s = Scene(ctx: ctx, size: size, t: t, tw: clock.tw, amp: max(0.08, clock.amp),
                      energy: clock.energy, stage: stage, clock: clock, groups: groups,
                      chosen: current, tint: tint, status: status, running: running, micOn: micOn,
                      outcome: deck.outcome, info: [info.next, info.due, info.body])
        s.singularity()
        if let p = pressed {
            let k = t - p.t
            if k < 2.2 {
                let col = deck.outcome[p.id].map { $0 ? Skin.good : Skin.recording } ?? Skin.cyan
                s.flash(p.label, col, k / 2.2)
            }
        }
    }

    /// The dark she gathers in, and the white she arrives in.
    private func overlay(_ ctx: GraphicsContext, _ size: CGSize, _ stage: Stage) {
        let all = Path(CGRect(origin: .zero, size: size))
        if stage.dark > 0 { ctx.fill(all, with: .color(.black.opacity(stage.dark))) }
        if stage.flash > 0 {
            var c = ctx
            c.blendMode = .plusLighter
            c.fill(all, with: .radialGradient(
                Gradient(colors: [.white.opacity(stage.flash), tint.opacity(stage.flash * 0.6)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: 0, endRadius: max(size.width, size.height) * 0.7))
        }
    }

    // ------------------------------------------------------------ the deck

    private var groups: [(name: String, buttons: [DeckButton])] {
        deck.groups.map { g in (g, deck.buttons.filter { $0.group == g && $0.id != DeckButton.sleepID }) }
    }

    private var current: String {
        groups.contains { $0.name == chosen } ? chosen : (groups.first?.name ?? "")
    }

    private func tap(_ screen: CGPoint) {
        // Back through the frame's shake and zoom to where things were drawn.
        let w = clock.size.width / 2, h = clock.size.height / 2
        let p = CGPoint(x: (screen.x - clock.offset.width - w) / clock.zoom + w,
                        y: (screen.y - clock.offset.height - h) / clock.zoom + h)
        let t = clock.now
        // A ring is a band, not a point: if the touch landed on one of the
        // information orbits, that is what he meant, whatever icon drifted
        // past it (Oscar, 2026-10-03 -- the first version lost every ring tap
        // to an app tip).
        let inRange = clock.hits
            .map { ($0, hypot($0.at.x - p.x, $0.at.y - p.y)) }
            .filter { $0.1 < $0.0.r }
        // An information ring wins over an app that happens to be drifting
        // past it: the icon is the smaller, more deliberate target, and the
        // ring is most of the screen (Oscar, 2026-10-03).
        let near = inRange.min { $0.1 < $1.1 }?.0
        // Nothing under the thumb means the rings: whichever one he was
        // nearest opens, because a tap in the empty space of this screen can
        // mean nothing else, and a band thin enough to miss is a control he
        // cannot find (Oscar, 2026-10-03).
        guard let near else {
            clock.waves.append((t, 0.8))
            let nearest = clock.rings.min {
                abs(hypot((p.x - clock.size.width / 2) / $0.ax,
                          (p.y - clock.size.height / 2) / $0.ay) - $0.r)
                < abs(hypot((p.x - clock.size.width / 2) / $1.ax,
                            (p.y - clock.size.height / 2) / $1.ay) - $1.r)
            }
            guard let nearest else { return }
            if clock.openRing == nearest.k, t - clock.openAt < 6 { clock.openRing = nil }
            else { clock.openRing = nearest.k; clock.openAt = t }
            return
        }
        switch near.tap {
        case .app(let g):
            chosen = g
            clock.waves.append((t, 1.2))
        case .button(let b):
            pressed = (b.label, b.id, t)
            clock.waves.append((t, 1.6))
            clock.glitchUntil = t + 0.25
            Task { await deck.run(b) }
        case .her:
            onHer()
        case .ring(let k):
            // Tapping the open one closes it again.
            if clock.openRing == k, t - clock.openAt < 6 {
                clock.openRing = nil
            } else {
                clock.openRing = k
                clock.openAt = t
            }
            clock.waves.append((t, 0.9))
        }
    }

    // ------------------------------------------------------------ finish

    private func scanlines(_ ctx: GraphicsContext, _ size: CGSize) {
        var p = Path()
        var y = 0.0
        while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
        ctx.fill(p, with: .color(.black.opacity(0.10)))
    }

    /// Bands of the screen slid sideways for a moment.
    private func glitch(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ stage: Stage) {
        let hits = clock.hits
        for _ in 0..<4 {
            let y = Double.random(in: 0..<size.height), h = Double.random(in: 4..<28)
            let band = CGRect(x: 0, y: y, width: size.width, height: h)
            var c = ctx
            c.clip(to: Path(band))
            c.fill(Path(band), with: .color(.black))
            c.translateBy(x: Double.random(in: -30...30), y: 0)
            draw(c, size, t, stage)
        }
        clock.hits = hits
        var c = ctx
        c.blendMode = .plusLighter
        c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Skin.mag.opacity(0.06)))
    }
}

// MARK: - Drawing

private let tau = Double.pi * 2

private func symbol(for group: String) -> String {
    switch group {
    case "Claude":           return "sparkle"
    case "lain":             return "triangle"
    case "Terminal":         return "terminal"
    case "Spotify":          return "music.note"
    case "Google Chrome":    return "globe"
    case "Finder":           return "command"
    case "Safari":           return "safari"
    case "Xcode":            return "hammer"
    case "Citrix Workspace": return "desktopcomputer"
    case "Codex":            return "chevron.left.forwardslash.chevron.right"
    default:                 return "circle.hexagongrid"
    }
}

private func hash(_ i: Int, _ k: Double) -> Double {
    let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
    return v - v.rounded(.down)
}

/// Where her arrival or departure is, as numbers the drawing reads.
private struct Stage {
    var rf = 1.0        // how far out everything sits; < 1 is being pulled in
    var eye = 1.0       // her eye's size
    var dim = 0.0       // 0 awake, 1 gone: how far her light reaches out of the hole
    var dark = 0.0      // black over everything, while she gathers herself
    var flash = 0.0     // white, the moment she arrives
    var kana = 0.0      // her name, huge, behind her
    /// The chant: 1 while it is burning in, falling slowly to 0 as it fades.
    var chant = 0.0
    /// How white-hot it is right now -- high for the first half second, so it
    /// reads as struck rather than faded up.
    var chantHeat = 0.0
    var shake = 0.0     // points of shake
    var presence = 1.0  // 0.5 asleep, 1 here
}

/// One frame of one look. A value: it draws and records where the tappable
/// things landed, nothing else.
private struct Scene {
    /// The words falling down the spiral arms, grouped to be drawn together:
    /// their colour (cyan, worked, failed) and their fade in twentieths.
    struct Fall: Hashable { let ink: Int, step: Int }
    /// The size the arms' words are made at, once; each is scaled from it.
    static let wordSize = 13.0
    /// Labels gathered to be drawn together: colour, fade in twentieths, glow.
    struct Lit: Hashable { let col: Color, step: Int, glow: Double }

    /// A label as a shape, added to the frame's batch rather than drawn: its
    /// letters are made once and kept (23.0).
    func label(_ s: String, _ p: CGPoint, _ col: Color, _ size: Double, glow: Double,
               opacity: Double, into batch: inout [Lit: Path]) {
        let step = Int((min(1, max(0, opacity)) * 20).rounded())
        guard step > 0 else { return }
        batch[Lit(col: col, step: step, glow: glow), default: Path()]
            .addPath(clock.word(s, size), transform: CGAffineTransform(translationX: p.x, y: p.y))
    }

    let ctx: GraphicsContext
    let size: CGSize
    /// Real time, for ripples; `tw` is time that runs faster while she
    /// speaks, for everything that turns.
    let t: Double
    let tw: Double
    let amp: Double
    /// Her speech, 0 when silent: what makes the whole screen move.
    let energy: Double
    /// Her level for everything but space: still while she speaks, so only
    /// the warp and the ripples carry her voice; the music's while idle.
    var deco: Double { energy > 0.02 ? 0.08 : amp }
    let stage: Stage
    let clock: RealmClock
    let groups: [(name: String, buttons: [DeckButton])]
    let chosen: String
    let tint: Color
    let status: String
    let running: Bool
    let micOn: Bool
    let outcome: [String: Bool]
    /// What the magenta rings say: next on the plan, what is due, the body.
    let info: [String]

    var cx: Double { size.width / 2 }
    var cy: Double { size.height / 2 }
    var M: Double { min(size.width, size.height) }
    var center: CGPoint { CGPoint(x: cx, y: cy) }

    /// Orbits are stretched to the screen's shape, so the long side is used
    /// too rather than leaving a band of nothing either side of a circle
    /// (Oscar, 2026-10-01). Her own ring and the halos stay round.
    var ax: Double { max(1, size.width / M * 0.92) }
    var ay: Double { max(1, size.height / M * 0.92) }
    func at(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: cx + cos(a) * r * ax, y: cy + sin(a) * r * ay) }
    /// The same, unstretched: her eye is round.
    func round(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r) }
    func orbit(_ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - r * ax, y: cy - r * ay, width: r * ax * 2, height: r * ay * 2))
    }
    func circle(_ p: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
    func hit(_ p: CGPoint, _ r: Double, _ tap: RealmClock.Tap) { clock.hits.append((p, r, tap)) }

    var lit: GraphicsContext { var c = ctx; c.blendMode = .plusLighter; return c }

    func text(_ s: String, _ p: CGPoint, _ col: Color, _ size: Double, glow: Double = 10,
              anchor: UnitPoint = .center, opacity: Double = 1, weight: Font.Weight = .medium) {
        var c = ctx
        c.opacity = opacity
        let txt = laid(s, col, size, weight)
        if glow > 0 {
            var g = c
            g.addFilter(.blur(radius: glow / 2))
            g.draw(txt, at: p, anchor: anchor)
        }
        c.draw(txt, at: p, anchor: anchor)
    }

    /// Text laid out once and drawn from the clock's store after that.
    func laid(_ s: String, _ col: Color, _ size: Double, _ weight: Font.Weight) -> GraphicsContext.ResolvedText {
        let key = RealmClock.Ink(s: s, size: size, weight: weight, col: col)
        if let r = clock.laid[key] { return r }
        if clock.laid.count > 3000 { clock.laid.removeAll() }
        let r = ctx.resolve(Text(s).font(.system(size: size, weight: weight, design: .monospaced)).foregroundColor(col))
        clock.laid[key] = r
        return r
    }

    func glyph(_ name: String, _ p: CGPoint, _ col: Color, _ size: Double, glow: Double = 14) {
        var img = ctx.resolve(Image(systemName: name))
        img.shading = .color(col)
        let w = img.size.width, h = img.size.height
        let k = size / max(w, h, 1)
        let rect = CGRect(x: p.x - w * k / 2, y: p.y - h * k / 2, width: w * k, height: h * k)
        var g = ctx
        g.addFilter(.blur(radius: glow / 2))
        g.draw(img, in: rect)
        ctx.draw(img, in: rect)
    }

    func halo(_ p: CGPoint, _ r: Double, _ col: Color, _ o: Double) {
        lit.fill(circle(p, r), with: .radialGradient(Gradient(colors: [col.opacity(o), col.opacity(0)]),
                                                     center: p, startRadius: 0, endRadius: r))
    }

    /// The glow ring: wide and faint to thin and bright, no hard edge. Drawn
    /// as the same three passes, but each as a ring of gradient rather than a
    /// blurred stroke: a blur is a whole-screen layer, and the eye alone took
    /// nine of them a frame (24.0).
    func softRing(_ p: CGPoint, _ r: Double, _ col: Color, _ lw: Double, _ o: Double = 1) {
        for (w, b, a) in [(lw * 5, M * 0.04, 0.2), (lw * 2.2, M * 0.015, 0.4), (lw, M * 0.004, 0.85)] {
            glowRing(lit, p, r, col, lw: w, blur: b, a * o)
        }
    }

    /// What a blurred circle's stroke looks like, without the blur: a radial
    /// gradient whose stops follow the bell a blur makes across the line.
    func glowRing(_ c: GraphicsContext, _ p: CGPoint, _ r: Double, _ col: Color,
                  lw: Double, blur: Double, _ a: Double) {
        let s = max(blur, lw * 0.3)
        let peak = a * min(1, lw / (2.5 * s))
        let outer = r + 3 * s
        guard outer > 0, peak > 0.002 else { return }
        var stops: [Gradient.Stop] = []
        for i in -4...4 {
            let x = Double(i) * 0.75 * s
            guard r + x >= 0 else { continue }
            stops.append(.init(color: col.opacity(peak * exp(-x * x / (2 * s * s))), location: (r + x) / outer))
        }
        c.fill(circle(p, outer), with: .radialGradient(Gradient(stops: stops), center: p,
                                                       startRadius: 0, endRadius: outer))
    }

    func softPath(_ path: Path, _ col: Color, _ lw: Double, _ o: Double = 1) {
        for (w, b, a) in [(lw * 5, M * 0.04, 0.2), (lw * 2.2, M * 0.015, 0.4), (lw, M * 0.004, 0.85)] {
            var c = lit
            c.addFilter(.blur(radius: b))
            c.stroke(path, with: .color(col.opacity(a * o)), lineWidth: w)
        }
    }

    func textOnCircle(_ s: String, r: Double, start: Double, _ col: Color, _ size: Double,
                      opacity: Double = 1, inward: Bool = false, stretched: Bool = true,
                      centred: Bool = false) {
        let ax = stretched ? self.ax : 1, ay = stretched ? self.ay : 1
        var c = ctx
        c.opacity = opacity
        // `centred` means "put the middle of these words at `start`", which is
        // what a label on an arc segment wants (Oscar, 2026-10-03).
        var start = start
        if centred {
            let width = Double(s.count) * size * 0.62
            start -= width / (2 * max(1, r))
        }
        // The whole ring is one shape, its letters placed along the orbit, and
        // filled once. Drawing each letter as text was most of the screen's
        // cost: a whole core with nothing happening (19.0).
        var ring = Path()
        var a = start
        for ch in s {
            // One lap at most: a longer string would write over its own start.
            guard a - start < tau else { break }
            let p = stretched ? at(r, a) : round(r, a)
            let tangent = atan2(cos(a) * ay, -sin(a) * ax)
            a += size * 0.62 / (r * hypot(ax * sin(a), ay * cos(a)))
            ring.addPath(clock.letter(ch, size), transform: CGAffineTransform(translationX: p.x, y: p.y)
                .rotated(by: tangent + (inward ? -Double.pi : 0)))
        }
        c.fill(ring, with: .color(col))
    }

    /// White cloud off a ring round her, rising, fuller when she is loud.
    func smoke(_ R: Double, n: Int = 40) {
        // Each puff a soft gradient of its own rather than all of them blurred:
        // the same cloud, no blur pass (24.0). Still one layer, so where puffs
        // overlap they cover each other instead of adding up to white.
        let b = R * 0.25
        lit.drawLayer { c in
            var c = c
            c.blendMode = .normal
            for i in 0..<n {
                let h1 = hash(i, 1), h2 = hash(i, 2), h3 = hash(i, 3)
                let life = (t * (0.09 + 0.07 * h1) * (1 + 0.8 * deco) + h2).truncatingRemainder(dividingBy: 1)
                let ang = h3 * tau + t * 0.18 + life * 0.9
                let r = R * (1 + 0.5 * life + 0.15 * deco)
                let p = CGPoint(x: cx + cos(ang) * r,
                                y: cy + sin(ang) * r * 0.4 + R * 0.3 - life * R * (1.1 + 0.6 * h1))
                let s = R * (0.12 + 0.24 * life) * (0.8 + 0.5 * deco + 0.3 * h2)
                let o = sin(life * .pi) * 0.22 * (0.6 + 0.4 * deco), out = s + 1.5 * b
                c.fill(circle(p, out), with: .radialGradient(
                    Gradient(stops: [.init(color: .white.opacity(o * 0.6), location: 0),
                                     .init(color: .white.opacity(o * 0.3), location: s / out),
                                     .init(color: .white.opacity(0), location: 1)]),
                    center: p, startRadius: 0, endRadius: out))
            }
        }
    }

    func flash(_ label: String, _ col: Color, _ k: Double) {
        softRing(center, M * (0.12 + k * 0.45), col, 2, 1 - k)
        text("> " + label.uppercased() + "_", CGPoint(x: cx, y: size.height - 60), col, 18,
             glow: 14, opacity: 1 - k * k, weight: .bold)
    }

    // ------------------------------------------------------- singularity

    /// Her eye is a black hole; every app is a spiral arm of words falling in.
    func singularity() {
        let st = stage, e = energy, pres = st.presence   // e: the warp only
        let g = clock.groove                                // the music, while she is away
        let Rh = M * 0.06 * st.rf
        func warp(_ r: Double, _ th: Double) -> CGPoint {
            var rr = r - (M * M * 0.012 * (1 + e + g * 2.2)) / (r + M * 0.04)
            for w in clock.waves {
                // Faster, wider and deeper than before: a syllable should
                // visibly shove space, not ripple it (Oscar, 2026-10-03).
                let wr = (t - w.t0) * M * 0.75, fade = 1 - (t - w.t0) / 3
                rr += exp(-pow((r - wr) / (M * 0.05), 2)) * M * 0.055 * w.s * fade
            }
            let twist = (1.6 + e * 1.2 + g * 1.4) * exp(-r / (M * 0.16)) + tw * 0.03
            return at(max(Rh, rr * st.rf), th + twist)
        }

        // space: a nebula wash under a glowing mesh, both pulled in by her,
        // brighter while she is here and brighter again while she speaks
        let reach = hypot(size.width, size.height) / 2
        let lum = pres
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.32).opacity(min(1, 0.9 * lum + deco * 0.1)),
                              Color(hue: frac(0.80 + clock.hue), saturation: 0.75, brightness: 0.24)
                                  .opacity(min(1, 0.7 * lum + g * 0.5)),
                              Color(red: 0.03, green: 0.03, blue: 0.08)]),
            center: center, startRadius: M * 0.05, endRadius: reach))
        var rings = Path(), spokes = Path(), marks = Path()
        for k in 1...20 {
            let r = pow(Double(k) / 20, 1.6) * reach
            for j in 0...100 {
                let p = warp(r, Double(j) / 100 * tau)
                j == 0 ? rings.move(to: p) : rings.addLine(to: p)
            }
        }
        for j in 0..<48 {
            var s = Path()
            for k in 0...50 {
                let p = warp(pow(Double(k) / 50, 1.6) * reach + 1, Double(j) / 48 * tau)
                k == 0 ? s.move(to: p) : s.addLine(to: p)
            }
            if j % 6 == 0 { marks.addPath(s) } else { spokes.addPath(s) }
        }
        // Her cyan at rest; with music the mesh turns through magenta and violet.
        let meshInk = clock.hue == clock.hue.rounded() ? Skin.cyan
            : Color(hue: palette(clock.hue), saturation: 0.72, brightness: 0.97)
        // The mesh's glow is a wide faint line under the thin one, not a blur:
        // a 3-point blur of the whole screen was the costliest pass left (24.0).
        lit.stroke(rings, with: .color(meshInk.opacity((0.22 + deco * 0.15) * 0.35 * pres)), lineWidth: 6)
        lit.stroke(marks, with: .color(Skin.mag.opacity(0.3 * 0.35 * pres)), lineWidth: 6)
        lit.stroke(rings, with: .color(meshInk.opacity((0.22 + deco * 0.1) * pres)), lineWidth: 1)
        lit.stroke(spokes, with: .color(Skin.cyan.opacity(0.12 * pres)), lineWidth: 1)
        lit.stroke(marks, with: .color(Skin.mag.opacity(0.28 * pres)), lineWidth: 1)

        // a beat of his music: a ring of light thrown out to the screen's edge,
        // brightest as it leaves, in the colour of that moment
        for b in clock.booms {
            let k = (t - b.t0) / 1.6, fade = (1 - k) * (1 - k)
            let ink = Color(hue: palette(b.hue), saturation: 0.8, brightness: 1)
            softPath(orbit(M * (0.07 + k * 0.62) * st.rf), ink, 1.5 + b.s, fade * pres)
            if k < 0.12 && b.s > 1.6 {
                lit.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(ink.opacity(0.10 * (1 - k / 0.12) * pres)))
            }
        }

        // the information rings (Oscar, 2026-10-01): magenta text on its own
        // dotted orbit, turning against its neighbours, warped by her like the
        // rest of space
        let ringInk = Color(red: 1, green: 0.42, blue: 0.70)
        for (k, (r, line)) in zip([M * 0.175, M * 0.255, M * 0.335], info).enumerated() where !line.isEmpty {
            let rr = r * st.rf
            let dir = k % 2 == 0 ? 1.0 : -1.0
            // Tapped, a ring stops being decoration: it swells, slows to a
            // stop and says its line straight across the screen, where it can
            // actually be read (Oscar, 2026-10-03). It settles back after six
            // seconds on its own.
            let openK = clock.openRing == k ? max(0, 1 - (t - clock.openAt) / 6) : 0
            let open = openK > 0 ? min(1, (t - clock.openAt) / 0.45) * (openK > 0.08 ? 1 : openK / 0.08) : 0
            lit.stroke(k == 0 ? circle(center, rr) : orbit(rr),
                       with: .color(Skin.mag.opacity((0.18 + 0.5 * open) * pres)),
                       style: StrokeStyle(lineWidth: 1 + 2 * open, dash: [2, 5],
                                          dashPhase: tw * 10 * dir))
            let full = line + "  ∴  "
            // Opened, the ring stops turning, doubles its letters and goes
            // white: the morph he asked for happens on the ring rather than
            // in a panel over it (Oscar, 2026-10-03).
            let big = (k == 0 ? 12 : 13) + 13 * open
            textOnCircle(open > 0.5 ? full : String(repeating: full, count: 6),
                         r: rr + 9 + 6 * open,
                         start: dir * tw * (0.05 - Double(k) * 0.012) * (1 - open),
                         open > 0.5 ? .white : ringInk, big,
                         opacity: (0.75 + 0.25 * open) * pres, stretched: k != 0)
            clock.rings.append((k, rr, ax, ay))
        }

        // her name, faint, wherever it drifted back to
        if let echo = clock.echo {
            let k = (t - echo.t0) / 3
            text("アリス", CGPoint(x: size.width * echo.x, y: size.height * echo.y), Skin.mag,
                 M * echo.size, glow: 24, opacity: sin(k * .pi) * 0.3 * pres, weight: .black)
        }

        // her name, huge, the moment she arrives
        if st.kana > 0 {
            text("アリス", CGPoint(x: cx, y: cy), .white, M * 0.32, glow: 40, opacity: st.kana, weight: .black)
        }


        // the clockwork rim
        let rim = M * 0.52 * st.rf
        var ticks = Path(), big = Path()
        for k in 0..<180 {
            let a = -tw * 0.05 + Double(k) / 180 * tau, long = k % 15 == 0
            let out = long ? 14 : 6.0
            var p = Path()
            p.move(to: at(rim, a)); p.addLine(to: at(rim + out, a))
            if long { big.addPath(p) } else { ticks.addPath(p) }
        }
        lit.stroke(ticks, with: .color(Skin.cyan.opacity(0.15 * pres)), lineWidth: 1)
        lit.stroke(big, with: .color(Skin.cyan.opacity(0.5 * pres)), lineWidth: 1)
        let now = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
        // At rest the rim carries the wake line too -- whether she can hear
        // 醒来, or why not -- which 20.0 promised and only Classic showed (21.0).
        let call = running ? status : "HOLD TO SUMMON ∴ " + status
        let rimText = "ARISU ∴ EVENT HORIZON ∴ \(now) ∴ \(chosen.uppercased()) ∴ \(call) ∴ "
        textOnCircle(rimText + rimText, r: rim + 26, start: tw * 0.03, Skin.mag, 10,
                     opacity: 0.5)

        // spiral arms of words. The apps sit on a smaller circle since
        // 2026-10-03 -- the outer ring belongs to the chosen app's actions now.
        let n = max(1, groups.count), Rmax = M * 0.295
        var falling: [Fall: Path] = [:]
        // The apps and the chosen app's actions are gathered over the frame
        // and drawn together after it, one glow per kind rather than one per
        // app, icon and label (23.0) -- the same cure 22.0 gave the falling
        // words.
        var labels: [Lit: Path] = [:]
        var arms = [Path(), Path()]          // the other apps', the chosen one's
        var icons: [(name: String, at: CGPoint, col: Color, size: Double)] = []
        for (i, g) in groups.enumerated() {
            let on = g.name == chosen, col = on ? Skin.mag : Skin.cyan
            let base = Double(i) / Double(n) * tau + tw * 0.07
            func pos(_ r: Double) -> CGPoint { warp(r, base + 2.2 * log(Rmax / r)) }
            var arm = Path()
            for k in 0...70 {
                let p = pos(Rmax - (Rmax - M * 0.06 * 1.4) * Double(k) / 70)
                k == 0 ? arm.move(to: p) : arm.addLine(to: p)
            }
            arms[on ? 1 : 0].addPath(arm)

            let tip = pos(Rmax)
            halo(tip, M * (on ? 0.07 : 0.04), col, (on ? 0.4 : 0.18) * pres)
            icons.append((symbol(for: g.name), tip, on ? .white : col, M * (on ? 0.06 : 0.045)))
            label(g.name.uppercased(), CGPoint(x: tip.x, y: tip.y + M * 0.04), col, 10, glow: 6,
                  opacity: on ? 1 : 0.55, into: &labels)
            hit(tip, M * 0.09, .app(g.name))

            // The chosen app's actions are drawn on the outer ring below;
            // only the other apps still trail theirs down the arm, faintly, so
            // the eye is not surrounded by words it cannot read.
            let count = max(1, g.buttons.count), speed = 0.04
            for (k, b) in g.buttons.enumerated() where !on {
                let u = (Double(k) / Double(count) + tw * speed + Double(i) * 0.13).truncatingRemainder(dividingBy: 1)
                let r = M * 0.06 * 1.3 + (Rmax * 0.93 - M * 0.06 * 1.3) * pow(1 - u, 1.4)
                let p = pos(r), q = pos(r * 0.97)
                var ang = atan2(q.y - p.y, q.x - p.x)
                if cos(ang) < 0 { ang += .pi }
                let near = 1 - r / Rmax
                let fs = 13 * (0.45 + 0.75 * r / Rmax)
                let alpha = 0.5 * min(1, u * 6) * min(1, (r - M * 0.06) / (M * 0.05))
                // In steps of 0.05: each step and colour is one shape below.
                let step = Int((max(0, alpha) * 20).rounded())
                guard step > 0 else { continue }
                let ink = outcome[b.id].map { $0 ? 1 : 2 } ?? 0
                let k = Scene.Fall(ink: ink, step: step)
                let s = fs / Scene.wordSize
                let place = CGAffineTransform(scaleX: s * (1 + near * near * 2.2), y: s * (1 - near * 0.5))  // spaghettified
                    .concatenating(CGAffineTransform(rotationAngle: ang))
                    .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
                falling[k, default: Path()].addPath(clock.word(b.label, Scene.wordSize), transform: place)
            }
        }
        // Every falling word drawn at once: one glow and one fill per colour
        // and step of fade, instead of a laid-out Text and a blur each, which
        // was more than half of Singularity's drawing (22.0).
        for (k, words) in falling {
            let ink = [Skin.cyan, Skin.good, Skin.recording][k.ink]
            var c = ctx
            c.opacity = Double(k.step) / 20
            var gl = c
            gl.addFilter(.blur(radius: 5))
            gl.fill(words, with: .color(ink))
            c.fill(words, with: .color(ink))
        }
        for (k, arm) in arms.enumerated() where !arm.isEmpty {
            let on = k == 1, col = on ? Skin.mag : Skin.cyan
            var a = lit
            a.addFilter(.blur(radius: 6))
            a.stroke(arm, with: .color(col.opacity((on ? 0.7 : 0.25) * pres)), lineWidth: on ? 5 : 3)
            lit.stroke(arm, with: .color(col.opacity((on ? 0.5 : 0.15) * pres)), lineWidth: on ? 1.5 : 1)
        }
        // Every icon's glow in one blurred layer, then the icons sharp.
        let resolved = icons.map { ic -> (GraphicsContext.ResolvedImage, CGRect) in
            var img = ctx.resolve(Image(systemName: ic.name))
            img.shading = .color(ic.col)
            let w = img.size.width, h = img.size.height, k = ic.size / max(w, h, 1)
            return (img, CGRect(x: ic.at.x - w * k / 2, y: ic.at.y - h * k / 2, width: w * k, height: h * k))
        }
        var iconGlow = ctx
        iconGlow.addFilter(.blur(radius: 7))
        iconGlow.drawLayer { l in for (img, r) in resolved { l.draw(img, in: r) } }
        for (img, r) in resolved { ctx.draw(img, in: r) }

        // ---- the actions of the chosen app, around the outside
        // (Oscar, 2026-10-03: no shared band, no background -- drawn the way
        // the applications are, each one its own lit point with its name
        // under it.)
        if let g = groups.first(where: { $0.name == chosen }), !g.buttons.isEmpty {
            let aR = M * 0.44 * st.rf
            let count = g.buttons.count
            let turn = tw * 0.012
            var rings: [Color: Path] = [:], dots: [Color: Path] = [:]
            for (k, b) in g.buttons.enumerated() {
                let a = Double(k) / Double(count) * tau + turn - .pi / 2
                let p = at(aR, a)
                let hot = outcome[b.id]
                let col = hot.map { $0 ? Skin.good : Skin.recording } ?? Skin.cyan
                halo(p, M * 0.035, col, 0.22 * pres)
                // a small mark rather than an icon: an action has no symbol
                rings[col, default: Path()].addPath(circle(p, M * 0.012))
                dots[col, default: Path()].addPath(circle(p, M * 0.004))
                label(b.label.uppercased(), CGPoint(x: p.x, y: p.y + M * 0.032),
                      .white, 11, glow: 6, opacity: 0.9 * pres, into: &labels)
                if !b.action.summary.isEmpty {
                    label(b.action.summary.uppercased(), CGPoint(x: p.x, y: p.y + M * 0.05),
                          col, 8, glow: 4, opacity: 0.45 * pres, into: &labels)
                }
                hit(p, M * 0.06, .button(b))
            }
            for (col, r) in rings { lit.stroke(r, with: .color(col.opacity(0.9 * pres)), lineWidth: 1.5) }
            for (col, d) in dots { lit.fill(d, with: .color(col.opacity(0.9 * pres))) }
        }
        for (k, words) in labels {
            var c = ctx
            c.opacity = Double(k.step) / 20
            var gl = c
            gl.addFilter(.blur(radius: k.glow / 2))
            gl.fill(words, with: .color(k.col))
            c.fill(words, with: .color(k.col))
        }

        // the eye
        let Ri = M * 0.12 * st.eye * (1 + deco * 0.15)
        halo(center, Ri * 3, tint, (0.08 + deco * 0.15) * pres)
        smoke(Ri)
        // Asleep, the light barely leaves the hole; awake, it reaches out. No
        // eyelids: he wanted it subtler than drawing an eye (Oscar, 2026-10-01).
        let open = 1 - st.dim
        let eyeCtx = ctx
        var eyeLit = eyeCtx
        eyeLit.blendMode = .plusLighter
        var fibres = Path(), red = Path()
        for k in 0..<160 {
            let a = Double(k) / 160 * tau + tw * 0.04
            let len = 0.47 + (0.08 + 0.45 * hash(k, 4) + (deco * 0.3) * sin(t * 9 + Double(k))) * open
            var p = Path()
            p.move(to: round(Ri * 0.45, a)); p.addLine(to: round(Ri * len, a + 0.05))
            if k % 9 == 0 { red.addPath(p) } else { fibres.addPath(p) }
        }
        eyeLit.stroke(fibres, with: .color(tint.opacity(0.4 * (0.3 + 0.7 * open))), lineWidth: 1)
        eyeLit.stroke(red, with: .color(Skin.mag.opacity(0.5 * open)), lineWidth: 1)
        // The pupil opens wide when she speaks: the hole is her voice.
        let pr = Ri * 0.44 * (1 - deco * 0.18)
        let split = 2.0
        for (dx, col, o) in [(-split, Color(red: 1, green: 0.2, blue: 0.33), 0.6),
                             (split, Color(red: 0.2, green: 0.53, blue: 1), 0.6)] {
            glowRing(eyeLit, CGPoint(x: cx + dx, y: cy), pr, col, lw: 3, blur: M * 0.01, o)
        }
        // The photon ring, soft (Oscar, 2026-10-01): blurred passes only, no
        // hard stroke, and the hole fades into it rather than being cut out.
        let photon = Color(red: 1, green: 0.95, blue: 0.75)
        for (w, blur, o) in [(pr * 0.5, pr * 0.25, 0.25), (pr * 0.2, pr * 0.1, 0.45), (pr * 0.07, pr * 0.04, 0.6)] {
            glowRing(eyeLit, center, pr, photon, lw: w, blur: blur, o)
        }
        eyeCtx.fill(circle(center, pr * 1.05), with: .radialGradient(
            Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                             .init(color: .black.opacity(0), location: 1)]),
            center: center, startRadius: 0, endRadius: pr * 1.05))
        softRing(center, Ri, micOn ? tint : Skin.cyan, M * 0.004 * (1 + deco), open)
        hit(center, Ri, .her)


        // the chant, struck into the screen in runes and left to cool
        // (Oscar, 2026-10-03: "bright thunder letter ... burn in the screen
        // and then slowly fade"). White-hot first, then the iron colour of a
        // cooling brand, with the glow outliving the stroke.
        if st.chant > 0, !clock.chant.isEmpty {
            let heat = st.chantHeat
            let runes = clock.chant
            // Big, but never wider than the screen: Sigrdrífumál is 34 runes.
            let fit = (size.width * 0.86) / (Double(runes.count) * 0.78)
            let size0 = min(M * 0.115, fit) * (1 + 0.06 * heat)
            let y = cy - M * 0.13
            // A flicker while it is still being struck, like a filament.
            let flick = heat > 0 ? (0.82 + 0.18 * sin(t * 47)) : 1
            // Lightning first, then the orange of iron off the forge.
            let hot = Color(red: 0.86, green: 0.95, blue: 1)
            let iron = Color(red: 1, green: 0.58, blue: 0.20)
            let ink = heat > 0.15 ? hot : iron
            var burn = lit
            burn.addFilter(.blur(radius: M * (0.02 + 0.05 * heat)))
            let face = Text(runes)
                .font(.system(size: size0, weight: .heavy, design: .serif))
            // three passes: a wide furnace glow, a tight one, the stroke
            burn.draw(face.foregroundColor(ink.opacity(st.chant * 0.85 * flick)),
                      at: CGPoint(x: cx, y: y))
            var mid = lit
            mid.addFilter(.blur(radius: M * 0.012))
            mid.draw(face.foregroundColor(ink.opacity(st.chant * 0.8 * flick)),
                     at: CGPoint(x: cx, y: y))
            ctx.draw(face.foregroundColor(ink.opacity(min(1, st.chant * (0.85 + heat)) * flick)),
                     at: CGPoint(x: cx, y: y))
            // the words themselves, small, under the runes, so he knows what
            // was said
            text(clock.chantLatin.uppercased(), CGPoint(x: cx, y: y + size0 * 0.95),
                 iron, 11, glow: 8, opacity: st.chant * 0.6)
        }

    }
}

// MARK: - What the rings say

/// lain's data.json, read every five minutes and boiled down to three lines
/// for the magenta rings (Oscar, 2026-10-01): what is next today, what is due,
/// and how the running and habits stand. The iPad only reads it.
@MainActor final class LainInfo: ObservableObject {
    @Published private(set) var next = ""
    @Published private(set) var due = ""
    @Published private(set) var body = ""
    /// The same reading, kept whole for the panel beside her (12.0).
    @Published private(set) var glance = Glance()

    static let url = URL(string: "https://architect-server.tailaa64e9.ts.net:8443/data.json")!

    func watch() async {
        while !Task.isCancelled {
            if let (data, _) = try? await URLSession.shared.data(from: Self.url),
               let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                read(d, now: Date())
            }
            try? await Task.sleep(for: .seconds(300))
        }
    }

    func read(_ d: [String: Any], now: Date) {
        let cal = Calendar.current
        let day = Self.iso(now)
        let wd = cal.component(.weekday, from: now) - 1          // 0 = Sunday, as the planner stores it
        let hm = now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())

        // the planner: today's blocks still to come
        let plan = (d["plan"] as? [String: [String: Any]] ?? [:]).values
        let ticked = (d["plog"] as? [String: [String: Any]])?[day] ?? [:]
        let today = plan.filter { p in
            let rep = p["rep"] as? String ?? "once"
            let days = p["days"] as? [Int] ?? []
            switch rep {
            case "daily": return true
            case "weekdays": return (1...5).contains(wd)
            case "weekends": return wd == 0 || wd == 6
            case "custom": return days.contains(wd)
            default: return (p["date"] as? String) == day
            }
        }
        let coming = today
            .filter { ($0["start"] as? String ?? "") >= hm && ticked[$0["id"] as? String ?? ""] == nil }
            .sorted { ($0["start"] as? String ?? "") < ($1["start"] as? String ?? "") }
            .prefix(4)
            .map { "\($0["start"] as? String ?? "") \(($0["title"] as? String ?? "").uppercased())" }
        next = coming.isEmpty ? "NOTHING LEFT ON THE PLAN TODAY" : "NEXT ∴ " + coming.joined(separator: " ∴ ")
        var g = Glance()
        g.loaded = true
        g.plan = Array(coming.prefix(3))

        // the todo: overdue and due within three days
        let soon = Self.iso(cal.date(byAdding: .day, value: 3, to: now)!)
        var open = 0
        var pressing: [(String, String)] = []
        for group in (d["todo"] as? [String: [String: Any]] ?? [:]).values {
            for t in group["tasks"] as? [[String: Any]] ?? [] where t["done"] as? Bool != true {
                open += 1
                if let when = t["due"] as? String, !when.isEmpty, when <= soon {
                    pressing.append((when, t["title"] as? String ?? ""))
                }
            }
        }
        let lines = pressing.sorted { $0.0 < $1.0 }.prefix(4).map { when, title in
            (when < day ? "! " : "") + String(title.uppercased().prefix(38)) + " · " + Self.short(when)
        }
        due = (lines.isEmpty ? "NOTHING DUE" : "DUE ∴ " + lines.joined(separator: " ∴ ")) + " ∴ \(open) OPEN"
        // The panel wraps to two lines, so it gets the whole title; the ring's
        // 38 characters cut "claim the €117 sustainable products refund"
        // to "...PRODUCTS RE" there (15.0).
        g.due = pressing.sorted { $0.0 < $1.0 }.prefix(3).map { when, title in
            (when < day ? "! " : "") + title.uppercased() + " · " + Self.short(when)
        }
        g.open = open

        // the race, the week's running, today's habits
        var parts: [String] = []
        if let r = Glance.raceDay(d), let left = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: r).day,
           left >= 0 {
            parts.append("P100K ∴ \(left) DAYS TO THE RACE")
            g.raceDays = left
        }
        let monday = cal.date(byAdding: .day, value: -((wd + 6) % 7), to: cal.startOfDay(for: now))!
        var km = 0.0
        for (k, v) in d["days"] as? [String: Any] ?? [:] {
            guard let date = Self.parse(k), date >= monday else { continue }
            km += (v as? Double) ?? ((v as? [String: Any])?["km"] as? Double) ?? 0
        }
        g.read(d, now: now, monday: monday)
        // While the plan runs the week is said against it (25.0): "12 KM
        // THIS WEEK" cannot tell a cutback week from a lost one.
        if let t = g.training {
            parts.append("WEEK \(t.week) \(t.phase.uppercased()) ∴ " + String(format: "%.0f OF %.0f KM", km, t.planned))
            if let p = g.pace { parts.append("RACE PACE " + Glance.perKm(p.perKm) + "/KM") }
        } else {
            parts.append(String(format: "%.0f KM THIS WEEK", km))
        }
        if let h = d["habits"] as? [String: Any], let list = h["list"] as? [[String: Any]] {
            let due = list.filter { ($0["days"] as? [Int] ?? []).contains(wd) }.count
            let done = ((h["log"] as? [String: [String]])?[day] ?? []).count
            parts.append("HABITS \(done)/\(due)")
        }
        body = parts.joined(separator: " ∴ ")
        glance = g
    }

    nonisolated static func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    nonisolated static func parse(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s)
    }
    nonisolated static func short(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        return d.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }
}

/// The fractional part, for hues that turn without end.
private func frac(_ x: Double) -> Double { x - x.rounded(.down) }

/// Her colours only: a hue that swings between cyan (0.52) and magenta (0.92)
/// through violet as `turn` runs, never through green or amber.
private func palette(_ turn: Double) -> Double { 0.52 + 0.4 * (0.5 - 0.5 * cos(turn * 2 * .pi)) }
