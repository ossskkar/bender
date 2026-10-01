import SwiftUI
import UIKit

/// The versions of the iPad app (Oscar, 2026-10-01). Classic is the screen
/// with the deck, the record panel and the chat; the other three are the whole
/// screen given to her voice, with the deck's apps and actions moving round
/// it. A four-finger swipe walks through them; the title's menu picks one.
enum Look: String, CaseIterable, Identifiable {
    case classic, singularity, sigil, clockwork
    static let key = "arisu.look"
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }

    func step(_ by: Int) -> Look {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + by + all.count) % all.count]
    }
}

/// Four fingers, left or right, anywhere on the window. iPadOS uses the same
/// gesture to switch apps when Multitasking gestures are on, and then the
/// system gets it first.
struct FourFingerSwipe: UIViewRepresentable {
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
                g.numberOfTouchesRequired = 4
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
/// the smoothed level, the ripples, where each tappable thing was last drawn.
private final class RealmClock {
    var start = Date()
    var amp = 0.0
    var lastAmp = 0.0
    var waves: [(t0: Double, s: Double)] = []
    var glitchUntil = 0.0
    var hits: [(at: CGPoint, r: Double, tap: Tap)] = []
    var trail: [CGPoint] = []

    enum Tap { case app(String), button(DeckButton), her }
}

struct RealmView: View {
    let look: Look
    /// Her own level, before the Mac's music is mixed in.
    let level: Double
    let idle: Bool
    let tint: Color
    let status: String
    let micOn: Bool
    let onHer: () -> Void

    @StateObject private var deck = Deck()
    @StateObject private var music = MacMusic()
    @State private var clock = RealmClock()
    @State private var chosen = ""
    @State private var pressed: (label: String, id: String, t: Double)?

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(clock.start)
                let target = idle ? max(level, music.level) : level
                clock.amp += (target - clock.amp) * 0.25
                clock.hits = []
                var c = ctx
                draw(&c, size, t)
                if t < clock.glitchUntil { glitch(ctx, size, t) }
                scanlines(ctx, size)
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap($0.location) })
        .ignoresSafeArea()
        .task { await deck.load() }
        .task { await deck.watchFront() }
        .task(id: idle) { if idle { await music.listen() } }
        .onChange(of: deck.front) { _, g in if !g.isEmpty { chosen = g } }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let s = Scene(ctx: ctx, size: size, t: t, amp: max(0.08, clock.amp), clock: clock,
                      groups: groups, chosen: current, tint: tint, status: status, micOn: micOn,
                      frontApp: deck.frontApp, outcome: deck.outcome)
        switch look {
        case .singularity: s.singularity()
        case .sigil:       s.sigil()
        case .clockwork:   s.clockwork()
        case .classic:     break
        }
        if let p = pressed {
            let k = t - p.t
            if k < 2.2 {
                let col = deck.outcome[p.id].map { $0 ? Skin.good : Skin.recording } ?? Skin.cyan
                s.flash(p.label, col, k / 2.2)
            }
        }
    }

    // ------------------------------------------------------------ the deck

    private var groups: [(name: String, buttons: [DeckButton])] {
        deck.groups.map { g in (g, deck.buttons.filter { $0.group == g && $0.id != DeckButton.sleepID }) }
    }

    private var current: String {
        groups.contains { $0.name == chosen } ? chosen : (groups.first?.name ?? "")
    }

    private func tap(_ p: CGPoint) {
        let near = clock.hits
            .map { ($0, hypot($0.at.x - p.x, $0.at.y - p.y)) }
            .filter { $0.1 < $0.0.r }
            .min { $0.1 < $1.1 }?.0
        let t = Date().timeIntervalSince(clock.start)
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
        ctx.fill(p, with: .color(.black.opacity(0.18)))
    }

    /// Bands of the screen slid sideways for a moment.
    private func glitch(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        for k in 0..<4 {
            let y = Double.random(in: 0..<size.height), h = Double.random(in: 4..<28)
            let band = CGRect(x: 0, y: y, width: size.width, height: h)
            var c = ctx
            c.clip(to: Path(band))
            c.fill(Path(band), with: .color(.black))
            c.translateBy(x: Double.random(in: -30...30), y: 0)
            draw(&c, size, t + Double(k) * 0.01)
        }
        var c = ctx
        c.blendMode = .plusLighter
        c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Skin.mag.opacity(0.06)))
    }
}

// MARK: - Drawing

private let blood = Color(red: 0.82, green: 0.13, blue: 0.25)
private let bone = Color(red: 0.94, green: 0.90, blue: 0.84)
private let tau = Double.pi * 2

private func symbol(for group: String) -> String {
    switch group {
    case "claude-code": return "sparkle"
    case "lain":        return "triangle"
    case "hermes":      return "bolt.horizontal"
    case "spotify":     return "music.note"
    case "chrome":      return "globe"
    case "mac":         return "command"
    default:            return "circle.hexagongrid"
    }
}

private func hash(_ i: Int, _ k: Double) -> Double {
    let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
    return v - v.rounded(.down)
}

/// One frame of one look. A value: it draws and records where the tappable
/// things landed, nothing else.
private struct Scene {
    let ctx: GraphicsContext
    let size: CGSize
    let t: Double
    let amp: Double
    let clock: RealmClock
    let groups: [(name: String, buttons: [DeckButton])]
    let chosen: String
    let tint: Color
    let status: String
    let micOn: Bool
    let frontApp: String
    let outcome: [String: Bool]

    var cx: Double { size.width / 2 }
    var cy: Double { size.height / 2 }
    var M: Double { min(size.width, size.height) }
    var center: CGPoint { CGPoint(x: cx, y: cy) }

    func at(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r) }
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
        for (w, b, a) in [(lw * 5, M * 0.04, 0.2), (lw * 2.2, M * 0.015, 0.4), (lw, M * 0.004, 0.85)] {
            var c = lit
            c.addFilter(.blur(radius: b))
            c.stroke(circle(p, r), with: .color(col.opacity(a * o)), lineWidth: w)
        }
    }

    func textOnCircle(_ s: String, r: Double, start: Double, _ col: Color, _ size: Double,
                      opacity: Double = 1, inward: Bool = false) {
        let step = size * 0.62 / r
        var c = ctx
        c.opacity = opacity
        // One lap at most: a longer string would write over its own start.
        for (i, ch) in s.prefix(Int(tau / step)).enumerated() {
            let a = start + Double(i) * step
            let p = at(r, a)
            var g = c
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(a + (inward ? -Double.pi / 2 : Double.pi / 2)))
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
            let life = (t * (0.09 + 0.07 * h1) * (1 + 0.8 * amp) + h2).truncatingRemainder(dividingBy: 1)
            let ang = h3 * tau + t * 0.18 + life * 0.9
            let r = R * (1 + 0.5 * life + 0.15 * amp)
            let p = CGPoint(x: cx + cos(ang) * r,
                            y: cy + sin(ang) * r * 0.4 + R * 0.3 - life * R * (1.1 + 0.6 * h1))
            let s = R * (0.12 + 0.24 * life) * (0.8 + 0.5 * amp + 0.3 * h2)
            c.fill(circle(p, s), with: .color(.white.opacity(sin(life * .pi) * 0.22 * (0.6 + 0.4 * amp))))
        }
    }

    func flash(_ label: String, _ col: Color, _ k: Double) {
        softRing(center, M * (0.12 + k * 0.45), col, 2, 1 - k)
        text("> " + label.uppercased() + "_", CGPoint(x: cx, y: size.height - 60), col, 18,
             glow: 14, opacity: 1 - k * k, weight: .bold)
    }

    /// Her, as each look draws her: a ring that breathes with her level.
    func voiceRing(_ R0: Double, _ col: Color) -> Double {
        let r = R0 * (1 + amp * 0.12) * (1 + 0.03 * sin(t * 1.1))
        halo(center, r * 2.2, col, 0.12 + amp * 0.18)
        smoke(r)
        softRing(center, r, col, M * 0.006 * (1 + amp))
        hit(center, r, .her)
        return r
    }

    // ------------------------------------------------------- singularity

    /// Her eye is a black hole; every app is a spiral arm of words falling in.
    func singularity() {
        if amp - clock.lastAmp > 0.18 { clock.waves.append((t, 0.6 + amp)) }
        clock.lastAmp = amp
        clock.waves.removeAll { t - $0.t0 > 3 }
        if Double.random(in: 0...1) < 0.003 { clock.glitchUntil = t + 0.15 }

        let Rh = M * 0.06
        func warp(_ r: Double, _ th: Double) -> CGPoint {
            var rr = r - (M * M * 0.012) / (r + M * 0.04)
            for w in clock.waves {
                let wr = (t - w.t0) * M * 0.55, fade = 1 - (t - w.t0) / 3
                rr += exp(-pow((r - wr) / (M * 0.035), 2)) * M * 0.03 * w.s * fade
            }
            let twist = 1.6 * exp(-r / (M * 0.16)) + t * 0.03
            return at(max(Rh, rr), th + twist)
        }

        // space
        let reach = hypot(size.width, size.height) / 2
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
        lit.stroke(rings, with: .color(Skin.cyan.opacity(0.07)), lineWidth: 1)
        lit.stroke(spokes, with: .color(Skin.cyan.opacity(0.04)), lineWidth: 1)
        lit.stroke(marks, with: .color(Skin.mag.opacity(0.09)), lineWidth: 1)

        // the clockwork rim
        let rim = M * 0.47
        var ticks = Path(), big = Path()
        for k in 0..<180 {
            let a = -t * 0.05 + Double(k) / 180 * tau, long = k % 15 == 0
            var p = Path()
            p.move(to: at(rim, a)); p.addLine(to: at(rim + (long ? 14 : 6), a))
            if long { big.addPath(p) } else { ticks.addPath(p) }
        }
        lit.stroke(ticks, with: .color(Skin.cyan.opacity(0.15)), lineWidth: 1)
        lit.stroke(big, with: .color(Skin.cyan.opacity(0.5)), lineWidth: 1)
        let now = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
        let rimText = "ARISU ∴ EVENT HORIZON ∴ \(now) ∴ \(chosen.uppercased()) ∴ \(status) ∴ "
        textOnCircle(rimText + rimText, r: rim + 26, start: t * 0.03, Skin.mag, 10, opacity: 0.5)

        // spiral arms of words
        let n = max(1, groups.count), Rmax = M * 0.44
        for (i, g) in groups.enumerated() {
            let on = g.name == chosen, col = on ? Skin.mag : Skin.cyan
            let base = Double(i) / Double(n) * tau + t * 0.07
            func pos(_ r: Double) -> CGPoint { warp(r, base + 2.2 * log(Rmax / r)) }
            var arm = Path()
            for k in 0...70 {
                let p = pos(Rmax - (Rmax - Rh * 1.4) * Double(k) / 70)
                k == 0 ? arm.move(to: p) : arm.addLine(to: p)
            }
            var a = lit
            a.addFilter(.blur(radius: 6))
            a.stroke(arm, with: .color(col.opacity(on ? 0.7 : 0.25)), lineWidth: on ? 5 : 3)
            lit.stroke(arm, with: .color(col.opacity(on ? 0.5 : 0.15)), lineWidth: on ? 1.5 : 1)

            let tip = pos(Rmax)
            halo(tip, M * (on ? 0.07 : 0.04), col, on ? 0.4 : 0.18)
            glyph(symbol(for: g.name), tip, on ? .white : col, M * (on ? 0.045 : 0.032))
            text(g.name.uppercased(), CGPoint(x: tip.x, y: tip.y + M * 0.04), col, 10, glow: 6,
                 opacity: on ? 1 : 0.55)
            hit(tip, M * 0.05, .app(g.name))

            let count = max(1, g.buttons.count), speed = on ? 0.018 : 0.05
            for (k, b) in g.buttons.enumerated() {
                let u = (Double(k) / Double(count) + t * speed + Double(i) * 0.13).truncatingRemainder(dividingBy: 1)
                let r = Rh * 1.3 + (Rmax * 0.93 - Rh * 1.3) * pow(1 - u, 1.4)
                let p = pos(r), q = pos(r * 0.97)
                var ang = atan2(q.y - p.y, q.x - p.x)
                if cos(ang) < 0 { ang += .pi }
                let near = 1 - r / Rmax
                let fs = (on ? 15 : 11) * (0.45 + 0.75 * r / Rmax)
                let alpha = (on ? 1 : 0.5) * min(1, u * 6) * min(1, (r - Rh) / (M * 0.05))
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
                if on && alpha > 0.3 { hit(p, M * 0.04, .button(b)) }
            }
        }

        // the eye
        let Ri = M * 0.12 * (1 + amp * 0.15)
        halo(center, Ri * 3, tint, 0.08 + amp * 0.15)
        smoke(Ri)
        var fibres = Path(), red = Path()
        for k in 0..<160 {
            let a = Double(k) / 160 * tau + t * 0.04
            let len = 0.55 + 0.45 * hash(k, 4) + amp * 0.3 * sin(t * 9 + Double(k))
            var p = Path()
            p.move(to: at(Ri * 0.45, a)); p.addLine(to: at(Ri * len, a + 0.05))
            if k % 9 == 0 { red.addPath(p) } else { fibres.addPath(p) }
        }
        lit.stroke(fibres, with: .color(tint.opacity(0.4)), lineWidth: 1)
        lit.stroke(red, with: .color(Skin.mag.opacity(0.5)), lineWidth: 1)
        let pr = Ri * 0.44 * (1 - amp * 0.18)
        softRing(CGPoint(x: cx - 2, y: cy), pr, Color(red: 1, green: 0.2, blue: 0.33), 2, 0.6)
        softRing(CGPoint(x: cx + 2, y: cy), pr, Color(red: 0.2, green: 0.53, blue: 1), 2, 0.6)
        softRing(center, pr, Color(red: 1, green: 0.95, blue: 0.75), 2.5, 0.9)
        ctx.fill(circle(center, pr * 0.94), with: .color(.black))
        softRing(center, Ri, micOn ? tint : Skin.cyan, M * 0.004 * (1 + amp))
        hit(center, Ri, .her)

        // a blink every few seconds
        let bp = t.truncatingRemainder(dividingBy: 7.3) / 7.3
        if bp > 0.96 {
            let close = sin((bp - 0.96) / 0.04 * .pi) * Ri * 1.05, L = Ri * 1.6
            for sgn in [-1.0, 1.0] {
                var lid = Path()
                let edge = cy + sgn * Ri * 1.3
                lid.move(to: CGPoint(x: cx - L, y: edge)); lid.addLine(to: CGPoint(x: cx + L, y: edge))
                lid.addQuadCurve(to: CGPoint(x: cx - L, y: edge),
                                 control: CGPoint(x: cx, y: edge - sgn * close * 2))
                ctx.fill(lid, with: .color(.black))
            }
        }
    }

    // ------------------------------------------------------- sigil

    /// Imu, without the star: a rosette of curves through the apps, rune rings
    /// turning against each other, the chosen app's actions drifting round her.
    func sigil() {
        let R = M * 0.42 * (1 + amp * 0.015), turn = t * 0.04
        halo(center, M * 0.75, blood, 0.16 + amp * 0.12)
        _ = voiceRing(M * 0.09, blood)
        softRing(center, M * 0.05, micOn ? tint : Skin.cyan, 1.5, 0.8)
        for (r, lw, o) in [(R, 2.0, 0.9), (R * 1.07, 1.0, 0.6), (R * 0.36, 1.0, 0.5)] {
            softRing(center, r, blood, lw, o)
        }
        let names = groups.map { $0.name.uppercased() }.joined(separator: " ✠ ") + " ✠ "
        textOnCircle(names + names, r: R * 1.035, start: -turn * 1.6, bone, 11, opacity: 0.55)
        let acts = groups.first { $0.name == chosen }?.buttons ?? []
        let runes = acts.map { $0.label.uppercased() }.joined(separator: " · ") + " · "
        textOnCircle(runes + runes, r: R * 0.33, start: turn * 2.4, bone, 10, opacity: 0.5, inward: true)

        // Nothing to draw a rose through until the deck has loaded.
        guard groups.count >= 2 else { return }
        let n = groups.count
        let P = (0..<n).map { at(R, turn + Double($0) / Double(n) * tau - .pi / 2) }
        let pull = 0.18 + 0.06 * sin(t * 0.6) + amp * 0.05
        var rose = Path()
        rose.move(to: P[0])
        for k in 0..<n {
            let mid = turn + (Double(k) + 0.5) / Double(n) * tau - .pi / 2
            rose.addQuadCurve(to: P[(k + 1) % n], control: at(R * pull, mid))
        }
        for (lw, b, o) in [(10.0, 20.0, 0.15), (3.0, 6.0, 0.5), (1.2, 1.0, 0.9)] {
            var c = lit
            c.addFilter(.blur(radius: b))
            c.stroke(rose, with: .color(blood.opacity(o)), lineWidth: lw * (1 + amp * 0.6))
        }
        for (i, p) in P.enumerated() {
            let on = groups[i].name == chosen
            lit.stroke(circle(p, M * 0.055), with: .color(blood.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 6], dashPhase: t * 20 * (i % 2 == 0 ? 1 : -1)))
            halo(p, M * (on ? 0.09 : 0.05), on ? bone : blood, on ? 0.45 : 0.3)
            glyph(symbol(for: groups[i].name), p, on ? .white : bone, M * (on ? 0.05 : 0.035))
            text(groups[i].name.uppercased(), CGPoint(x: p.x, y: p.y + M * 0.05), bone, 11, glow: 6,
                 opacity: on ? 1 : 0.5)
            hit(p, M * 0.06, .app(groups[i].name))
        }
        // the actions drift round a ring of their own between her and the rose
        let ra = R * 0.6
        for (k, b) in acts.enumerated() {
            let a = Double(k) / Double(max(1, acts.count)) * tau - t * 0.05
            let p = at(ra + sin(t * 0.7 + Double(k)) * M * 0.01, a)
            let ink = outcome[b.id].map { $0 ? Skin.good : Skin.recording } ?? bone
            text(b.label.uppercased(), p, ink, 14, glow: 12, weight: .semibold)
            hit(p, M * 0.045, .button(b))
        }
    }

    // ------------------------------------------------------- clockwork

    /// Rings of words turning against each other under a beam at twelve.
    func clockwork() {
        _ = voiceRing(M * 0.11, micOn ? tint : Skin.cyan)
        var beam = Path()
        beam.move(to: CGPoint(x: cx, y: cy - M * 0.14))
        beam.addLine(to: CGPoint(x: cx - M * 0.05, y: cy - M * 0.48))
        beam.addLine(to: CGPoint(x: cx + M * 0.05, y: cy - M * 0.48))
        beam.closeSubpath()
        lit.fill(beam, with: .linearGradient(
            Gradient(colors: [Skin.cyan.opacity(0), Skin.cyan.opacity(0.10 + amp * 0.15)]),
            startPoint: CGPoint(x: cx, y: cy - M * 0.48), endPoint: CGPoint(x: cx, y: cy - M * 0.15)))

        let acts = groups.first { $0.name == chosen }?.buttons ?? []
        let day = Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
        let time = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        let info = [time, day, "MAC // " + (frontApp.isEmpty ? "—" : frontApp.uppercased()),
                    micOn ? "MIC ON" : "MIC OFF", status]
        enum Kind { case app, act, info }
        let rings: [(r: Double, items: [String], w: Double, col: Color, size: Double, kind: Kind)] = [
            (M * 0.22, groups.map { $0.name.uppercased() }, t * 0.09, Skin.cyan, 13, .app),
            (M * 0.31, acts.map { $0.label.uppercased() }, -t * 0.06, Skin.mag, 13, .act),
            (M * 0.39, info, t * 0.035, Skin.ink, 11, .info),
        ]
        for ring in rings {
            var ticks = Path(), big = Path()
            for k in 0..<120 {
                let a = ring.w + Double(k) / 120 * tau, long = k % 10 == 0
                var p = Path()
                p.move(to: at(ring.r + 14, a)); p.addLine(to: at(ring.r + (long ? 22 : 18), a))
                if long { big.addPath(p) } else { ticks.addPath(p) }
            }
            lit.stroke(ticks, with: .color(ring.col.opacity(0.12)), lineWidth: 1)
            lit.stroke(big, with: .color(ring.col.opacity(0.4)), lineWidth: 1)

            let n = max(1, ring.items.count)
            for (k, s) in ring.items.enumerated() {
                let start = ring.w + Double(k) / Double(n) * tau - .pi / 2
                let span = Double(s.count) * ring.size * 0.62 / ring.r
                let mid = (start + span / 2).truncatingRemainder(dividingBy: tau)
                let m = mid < 0 ? mid + tau : mid
                let under = min(abs(m - tau * 0.75), tau - abs(m - tau * 0.75)) < 0.18
                var col = ring.col
                if ring.kind == .app && ring.items[k] == chosen.uppercased() { col = .white }
                if ring.kind == .act, let ok = outcome[acts[k].id] { col = ok ? Skin.good : Skin.recording }
                textOnCircle(s, r: ring.r, start: start, under ? .white : col, ring.size,
                             opacity: under || col == .white ? 1 : 0.5)
                let p = at(ring.r, start + span / 2)
                switch ring.kind {
                case .app: hit(p, M * 0.045, .app(groups[k].name))
                case .act: hit(p, M * 0.045, .button(acts[k]))
                case .info: break
                }
            }
        }
        if let g = groups.first(where: { $0.name == chosen }) {
            glyph(symbol(for: g.name), center, Skin.cyan, M * 0.06, glow: 20)
        }
    }
}
