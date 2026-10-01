import SwiftUI
import UIKit

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
    let start = Date()
    var last = 0.0
    var tw = 0.0
    var amp = 0.0
    var energy = 0.0
    var lastAmp = 0.0
    var waves: [(t0: Double, s: Double)] = []
    var glitchUntil = 0.0
    var summonAt: Double?
    var dismissAt: Double?
    var banged = false
    /// The shake and zoom the last frame was drawn with, to map a tap back.
    var offset = CGSize.zero
    var zoom = 1.0
    var size = CGSize.zero
    var hits: [(at: CGPoint, r: Double, tap: Tap)] = []

    enum Tap { case app(String), button(DeckButton), her }

    var now: Double { Date().timeIntervalSince(start) }
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

    @StateObject private var deck = Deck()
    @StateObject private var music = MacMusic()
    @StateObject private var info = LainInfo()
    @State private var clock = RealmClock()
    @State private var chosen = ""
    @State private var pressed: (label: String, id: String, t: Double)?

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(clock.start)
                step(t)
                clock.size = size
                let stage = stage(t)
                clock.hits = []
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
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onSummon() }
                .exclusively(before: SpatialTapGesture().onEnded { tap($0.location) })
        )
        .ignoresSafeArea()
        .task { await deck.load() }
        .task { await deck.watchFront() }
        .task { await info.watch() }
        .task(id: idle) { if idle { await music.listen() } }
        .onChange(of: deck.front) { _, g in if !g.isEmpty { chosen = g } }
        .onChange(of: running) { _, on in
            if on { clock.summonAt = clock.now; clock.dismissAt = nil; clock.banged = false }
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
        let target = idle ? max(level, music.level) : level
        clock.amp += (target - clock.amp) * 0.25
        clock.energy += ((speaking ? clock.amp : 0) - clock.energy) * 0.3
        clock.tw += dt * (running ? 1 : 0.5)
        // A syllable or a beat sends a ripple through space; hers are bigger.
        if clock.amp - clock.lastAmp > (speaking ? 0.07 : 0.18) {
            // Small ones for speech; the big one is kept for her arrival (Oscar, 2026-10-01).
            clock.waves.append((t, speaking ? 0.25 + clock.amp * 0.5 : 0.6 + clock.amp))
        }
        clock.lastAmp = clock.amp
        clock.waves.removeAll { t - $0.t0 > 3 }
        if Double.random(in: 0...1) < 0.003 { clock.glitchUntil = t + 0.12 }
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
        } else if let d = clock.dismissAt, t - d < 1.4 {
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
        let near = clock.hits
            .map { ($0, hypot($0.at.x - p.x, $0.at.y - p.y)) }
            .filter { $0.1 < $0.0.r }
            .min { $0.1 < $1.1 }?.0
        let t = clock.now
        guard let near else { clock.waves.append((t, 0.8)); return }
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
    var shake = 0.0     // points of shake
    var presence = 1.0  // 0.5 asleep, 1 here
}

/// One frame of one look. A value: it draws and records where the tappable
/// things landed, nothing else.
private struct Scene {
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
        let txt = Text(s).font(.system(size: size, weight: weight, design: .monospaced)).foregroundColor(col)
        if glow > 0 {
            var g = c
            g.addFilter(.blur(radius: glow / 2))
            g.draw(txt, at: p, anchor: anchor)
        }
        c.draw(txt, at: p, anchor: anchor)
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

    /// The glow ring: wide and faint to thin and bright, no hard edge.
    func softRing(_ p: CGPoint, _ r: Double, _ col: Color, _ lw: Double, _ o: Double = 1) {
        softPath(circle(p, r), col, lw, o)
    }

    func softPath(_ path: Path, _ col: Color, _ lw: Double, _ o: Double = 1) {
        for (w, b, a) in [(lw * 5, M * 0.04, 0.2), (lw * 2.2, M * 0.015, 0.4), (lw, M * 0.004, 0.85)] {
            var c = lit
            c.addFilter(.blur(radius: b))
            c.stroke(path, with: .color(col.opacity(a * o)), lineWidth: w)
        }
    }

    func textOnCircle(_ s: String, r: Double, start: Double, _ col: Color, _ size: Double,
                      opacity: Double = 1, inward: Bool = false, stretched: Bool = true) {
        let ax = stretched ? self.ax : 1, ay = stretched ? self.ay : 1
        var c = ctx
        c.opacity = opacity
        var a = start
        for ch in s {
            // One lap at most: a longer string would write over its own start.
            guard a - start < tau else { break }
            let p = stretched ? at(r, a) : round(r, a)
            let tangent = atan2(cos(a) * ay, -sin(a) * ax)
            a += size * 0.62 / (r * hypot(ax * sin(a), ay * cos(a)))
            var g = c
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(tangent + (inward ? -Double.pi : 0)))
            g.draw(Text(String(ch)).font(.system(size: size, design: .monospaced)).foregroundColor(col),
                   at: .zero)
        }
    }

    /// White cloud off a ring round her, rising, fuller when she is loud.
    func smoke(_ R: Double, n: Int = 40) {
        var c = lit
        c.addFilter(.blur(radius: R * 0.25))
        for i in 0..<n {
            let h1 = hash(i, 1), h2 = hash(i, 2), h3 = hash(i, 3)
            let life = (t * (0.09 + 0.07 * h1) * (1 + 0.8 * deco) + h2).truncatingRemainder(dividingBy: 1)
            let ang = h3 * tau + t * 0.18 + life * 0.9
            let r = R * (1 + 0.5 * life + 0.15 * deco)
            let p = CGPoint(x: cx + cos(ang) * r,
                            y: cy + sin(ang) * r * 0.4 + R * 0.3 - life * R * (1.1 + 0.6 * h1))
            let s = R * (0.12 + 0.24 * life) * (0.8 + 0.5 * deco + 0.3 * h2)
            c.fill(circle(p, s), with: .color(.white.opacity(sin(life * .pi) * 0.22 * (0.6 + 0.4 * deco))))
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
        let Rh = M * 0.06 * st.rf
        func warp(_ r: Double, _ th: Double) -> CGPoint {
            var rr = r - (M * M * 0.012 * (1 + e)) / (r + M * 0.04)
            for w in clock.waves {
                let wr = (t - w.t0) * M * 0.55, fade = 1 - (t - w.t0) / 3
                rr += exp(-pow((r - wr) / (M * 0.035), 2)) * M * 0.03 * w.s * fade
            }
            let twist = (1.6 + e * 1.2) * exp(-r / (M * 0.16)) + tw * 0.03
            return at(max(Rh, rr * st.rf), th + twist)
        }

        // space: a nebula wash under a glowing mesh, both pulled in by her,
        // brighter while she is here and brighter again while she speaks
        let reach = hypot(size.width, size.height) / 2
        let lum = pres
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.32).opacity(min(1, 0.9 * lum + deco * 0.1)),
                                                            Color(red: 0.16, green: 0.06, blue: 0.22).opacity(0.7 * lum),
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
        let meshInk = Skin.cyan
        var meshGlow = lit
        meshGlow.addFilter(.blur(radius: 3))
        meshGlow.stroke(rings, with: .color(meshInk.opacity((0.22 + deco * 0.15) * pres)), lineWidth: 2)
        meshGlow.stroke(marks, with: .color(Skin.mag.opacity(0.3 * pres)), lineWidth: 2)
        lit.stroke(rings, with: .color(meshInk.opacity((0.22 + deco * 0.1) * pres)), lineWidth: 1)
        lit.stroke(spokes, with: .color(Skin.cyan.opacity(0.12 * pres)), lineWidth: 1)
        lit.stroke(marks, with: .color(Skin.mag.opacity(0.28 * pres)), lineWidth: 1)

        // the information rings (Oscar, 2026-10-01): magenta text on its own
        // dotted orbit, turning against its neighbours, warped by her like the
        // rest of space
        let ringInk = Color(red: 1, green: 0.42, blue: 0.70)
        for (k, (r, line)) in zip([M * 0.2, M * 0.31, M * 0.395], info).enumerated() where !line.isEmpty {
            let rr = r * st.rf
            let dir = k % 2 == 0 ? 1.0 : -1.0
            lit.stroke(k == 0 ? circle(center, rr) : orbit(rr), with: .color(Skin.mag.opacity(0.18 * pres)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 5], dashPhase: tw * 10 * dir))
            let full = line + "  ∴  "
            textOnCircle(String(repeating: full, count: 6), r: rr + 9, start: dir * tw * (0.05 - Double(k) * 0.012),
                         ringInk, k == 0 ? 12 : 13, opacity: 0.75 * pres, stretched: k != 0)
        }

        // her name, huge, the moment she arrives
        if st.kana > 0 {
            text("アリス", CGPoint(x: cx, y: cy), .white, M * 0.32, glow: 40, opacity: st.kana, weight: .black)
        }

        // the clockwork rim
        let rim = M * 0.47 * st.rf
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
        let call = running ? status : "HOLD TO SUMMON"
        let rimText = "ARISU ∴ EVENT HORIZON ∴ \(now) ∴ \(chosen.uppercased()) ∴ \(call) ∴ "
        textOnCircle(rimText + rimText, r: rim + 26, start: tw * 0.03, Skin.mag, 10,
                     opacity: 0.5)

        // spiral arms of words
        let n = max(1, groups.count), Rmax = M * 0.44
        for (i, g) in groups.enumerated() {
            let on = g.name == chosen, col = on ? Skin.mag : Skin.cyan
            let base = Double(i) / Double(n) * tau + tw * 0.07
            func pos(_ r: Double) -> CGPoint { warp(r, base + 2.2 * log(Rmax / r)) }
            var arm = Path()
            for k in 0...70 {
                let p = pos(Rmax - (Rmax - M * 0.06 * 1.4) * Double(k) / 70)
                k == 0 ? arm.move(to: p) : arm.addLine(to: p)
            }
            var a = lit
            a.addFilter(.blur(radius: 6))
            a.stroke(arm, with: .color(col.opacity((on ? 0.7 : 0.25) * pres)), lineWidth: on ? 5 : 3)
            lit.stroke(arm, with: .color(col.opacity((on ? 0.5 : 0.15) * pres)), lineWidth: on ? 1.5 : 1)

            let tip = pos(Rmax)
            halo(tip, M * (on ? 0.07 : 0.04), col, (on ? 0.4 : 0.18) * pres)
            glyph(symbol(for: g.name), tip, on ? .white : col, M * (on ? 0.06 : 0.045))
            text(g.name.uppercased(), CGPoint(x: tip.x, y: tip.y + M * 0.04), col, 10, glow: 6,
                 opacity: on ? 1 : 0.55)
            hit(tip, M * 0.09, .app(g.name))

            let count = max(1, g.buttons.count), speed = on ? 0.008 : 0.04
            for (k, b) in g.buttons.enumerated() {
                let u = (Double(k) / Double(count) + tw * speed + Double(i) * 0.13).truncatingRemainder(dividingBy: 1)
                let r = M * 0.06 * 1.3 + (Rmax * 0.93 - M * 0.06 * 1.3) * pow(1 - u, 1.4)
                let p = pos(r), q = pos(r * 0.97)
                var ang = atan2(q.y - p.y, q.x - p.x)
                if cos(ang) < 0 { ang += .pi }
                let near = 1 - r / Rmax
                let fs = (on ? 22 : 13) * (0.45 + 0.75 * r / Rmax)
                let alpha = (on ? 1 : 0.5) * min(1, u * 6) * min(1, (r - M * 0.06) / (M * 0.05))
                var c = ctx
                c.translateBy(x: p.x, y: p.y)
                c.rotate(by: .radians(ang))
                c.scaleBy(x: 1 + near * near * 2.2, y: 1 - near * 0.5)       // spaghettified
                c.opacity = max(0, alpha)
                let ink = outcome[b.id].map { $0 ? Skin.good : Skin.recording } ?? (on ? .white : col)
                let txt = Text(b.label).font(.system(size: fs, weight: .medium, design: .monospaced))
                    .foregroundColor(ink)
                var gl = c
                gl.addFilter(.blur(radius: 5))
                gl.draw(txt, at: .zero)
                c.draw(txt, at: .zero)
                if on && alpha > 0.3 { hit(p, M * 0.075, .button(b)) }
            }
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
            var c = eyeLit
            c.addFilter(.blur(radius: M * 0.01))
            c.stroke(circle(CGPoint(x: cx + dx, y: cy), pr), with: .color(col.opacity(o)), lineWidth: 3)
        }
        // The photon ring, soft (Oscar, 2026-10-01): blurred passes only, no
        // hard stroke, and the hole fades into it rather than being cut out.
        let photon = Color(red: 1, green: 0.95, blue: 0.75)
        for (w, blur, o) in [(pr * 0.5, pr * 0.25, 0.25), (pr * 0.2, pr * 0.1, 0.45), (pr * 0.07, pr * 0.04, 0.6)] {
            var c = eyeLit
            c.addFilter(.blur(radius: blur))
            c.stroke(circle(center, pr), with: .color(photon.opacity(o)), lineWidth: w)
        }
        eyeCtx.fill(circle(center, pr * 1.05), with: .radialGradient(
            Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                             .init(color: .black.opacity(0), location: 1)]),
            center: center, startRadius: 0, endRadius: pr * 1.05))
        softRing(center, Ri, micOn ? tint : Skin.cyan, M * 0.004 * (1 + deco), open)
        hit(center, Ri, .her)
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

        // the race, the week's running, today's habits
        var parts: [String] = []
        if let race = (d["settings"] as? [String: Any])?["raceDate"] as? String,
           let r = Self.parse(race), let left = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: r).day,
           left >= 0 {
            parts.append("P100K ∴ \(left) DAYS TO THE RACE")
        }
        let monday = cal.date(byAdding: .day, value: -((wd + 6) % 7), to: cal.startOfDay(for: now))!
        var km = 0.0
        for (k, v) in d["days"] as? [String: Any] ?? [:] {
            guard let date = Self.parse(k), date >= monday else { continue }
            km += (v as? Double) ?? ((v as? [String: Any])?["km"] as? Double) ?? 0
        }
        parts.append(String(format: "%.0f KM THIS WEEK", km))
        if let h = d["habits"] as? [String: Any], let list = h["list"] as? [[String: Any]] {
            let due = list.filter { ($0["days"] as? [Int] ?? []).contains(wd) }.count
            let done = ((h["log"] as? [String: [String]])?[day] ?? []).count
            parts.append("HABITS \(done)/\(due)")
        }
        body = parts.joined(separator: " ∴ ")
    }

    private static func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s)
    }
    private static func short(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        return d.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }
}
