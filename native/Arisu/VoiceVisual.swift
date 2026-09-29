import SwiftUI

/// Her face, as a voice visual.
///
/// The portrait and the Live2D model are a picture of a person; these are a
/// picture of a voice. Five of them, all spheres, all in lain's own skin --
/// cyan and magenta on void, a hard bloom, scanlines and a vignette, which is
/// what makes the iPad look like the dashboard rather than like a toy
/// (Oscar, 2026-09-28). He picks one in Settings; the portrait is still there.
///
/// The shapes come from `native/voice-visuals.html`, the page of 67 animated
/// mockups he narrowed down. Anything changed here should be changed there
/// too, or the next round of picking is done against the wrong picture.
enum FaceStyle: String, CaseIterable, Identifiable {
    /// The five spheres, then the five flat ones he picked out of the same
    /// page (25, 11, 9, 3, 40 there; 2026-09-29). A sphere reads as a body in
    /// a room; a flat one reads as a signal on a screen, and he wanted both.
    ///
    /// `portrait` is what the still, the Live2D models and the VRM were drawn
    /// as. He took them out of the picker on 2026-09-29 -- her face is one of
    /// the drawn ten now -- so the case stays only to read an old saved
    /// choice, and `offered` is what the picker shows. `FaceView` and the
    /// model pages are untouched on disk: bringing them back is this list.
    case portrait, halo, bubble, groove, trail, ribbon
    case ring, liquid, lissajous, bubbles, aurora
    var id: String { rawValue }

    /// The five he kept (Oscar, 2026-09-29): halo, groove, trail, bubble and
    /// liquid were crossed off the grid. They still draw, so a saved one keeps
    /// working and putting one back is this line.
    static let offered: [FaceStyle] = [.ribbon, .ring, .lissajous, .bubbles, .aurora]

    var label: String {
        switch self {
        case .portrait:  return "Portrait"
        case .halo:      return "Halo sphere"
        case .bubble:    return "Bubble sphere"
        case .groove:    return "Groove sphere"
        case .trail:     return "Trail sphere"
        case .ribbon:    return "Ribbon sphere"
        case .ring:      return "Halo ring"
        case .liquid:    return "Liquid"
        case .lissajous: return "Lissajous"
        case .bubbles:   return "Bubbles"
        case .aurora:    return "Aurora"
        }
    }
}

/// What she is doing. The same four states the legend names, and the only
/// thing this view is told about her -- it decides how they look.
enum VoiceState { case idle, listening, thinking, speaking }

/// How a state moves. Colour alone told him *which* state only if he
/// remembered the legend; the movement tells him what she is doing without
/// one (Oscar, 2026-09-29). Read it as: she turns slowly and breathes when
/// there is nothing to do, leans in and pulls the rings inward while he
/// talks, spins fast and jitters while she works, and pushes rings outward
/// with her own voice while she speaks.
struct Motion {
    /// Turns of the sphere per second-ish.
    let spin: Double
    /// How fast the surface ripples.
    let wobble: Double
    /// How far it ripples, against her level.
    let depth: Double
    /// Bloom, which is also how awake she looks.
    let bloom: Double
    /// Segments break their line and slip -- working, not idling.
    let jitter: Double
    /// +1 pushes waves out of her (speaking), -1 pulls them in (listening),
    /// 0 leaves the surface alone. This is the one that reads across a room.
    let flow: Double
    /// How much she breathes: the whole sphere swelling and settling on a
    /// four-and-a-half second cycle. Full while she waits, because a thing
    /// that only twitches at its surface reads as a screensaver and a thing
    /// that breathes reads as alive (Oscar, 2026-09-29). Nearly off while she
    /// talks -- her voice is already moving it.
    let breath: Double

    static func of(_ state: VoiceState) -> Motion {
        switch state {
        case .idle:      return Motion(spin: 0.16, wobble: 0.8, depth: 0.35,
                                       bloom: 0.45, jitter: 0, flow: 0, breath: 1.0)
        case .listening: return Motion(spin: 0.34, wobble: 2.0, depth: 0.85,
                                       bloom: 0.85, jitter: 0, flow: -1, breath: 0.45)
        case .thinking:  return Motion(spin: 1.40, wobble: 3.6, depth: 0.5,
                                       bloom: 0.7, jitter: 1, flow: 0, breath: 0.25)
        case .speaking:  return Motion(spin: 0.52, wobble: 4.2, depth: 0.95,
                                       bloom: 1.25, jitter: 0, flow: 1, breath: 0.15)
        }
    }
}

struct VoiceVisual: View {
    let style: FaceStyle
    /// What she is doing, which is the movement as well as the colour.
    var state: VoiceState = .idle
    /// 0…1, her own level -- the same number the portrait's mouth uses.
    let amplitude: Double
    /// The state colour: indigo waiting, green hearing him, magenta working,
    /// cyan talking. It is the whole state cue here, so it is never mixed
    /// with the character's mood.
    let tint: Color
    /// His three dials (Settings ▸ Face). How big she is drawn, how hard she
    /// glows, and how fast everything moves -- a desk at arm's length and a
    /// room across the sofa want different answers, and the glow sliders that
    /// already existed only ever reached the portrait (Oscar, 2026-09-29).
    var scale: Double = 1
    var bloom: Double = 1
    var speed: Double = 1

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate * max(0.1, speed)
                let w = min(size.width, size.height)
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                draw(ctx, w: w * max(0.2, scale), t: t)
                // The dashboard's own finish, over whatever was drawn.
                vignette(ctx, w: w)
                scanlines(ctx, w: w)
            }
        }
        .drawingGroup()          // one Metal layer: 60 fps on the 2020 iPad
        .allowsHitTesting(false)
    }

    // ----------------------------------------------------------------- bits

    private var mag: Color { Skin.mag }

    /// Her level, with a floor. A sphere that is exactly still while she waits
    /// reads as a crash rather than as patience, so there is always a slow
    /// breath under it -- `breath(t)` at rest, her own level once she has one.
    private func amp(_ t: Double) -> Double {
        let live = max(0, min(1, amplitude))
        let breath = 0.10 + 0.045 * sin(t * 0.9)
        return max(breath, live)
    }

    private var m: Motion {
        let base = Motion.of(state)
        guard bloom != 1 else { return base }
        return Motion(spin: base.spin, wobble: base.wobble, depth: base.depth,
                      bloom: base.bloom * bloom, jitter: base.jitter,
                      flow: base.flow, breath: base.breath)
    }

    /// One breath, as a scale on the whole sphere. Not a sine: a breath is a
    /// quick draw in and a long let out, and the difference between the two is
    /// what makes it read as breathing rather than as pulsing. 5.5 s -- eleven
    /// a minute, a calm adult at rest; 4.5 read as slightly hurried.
    private func breath(_ t: Double) -> Double {
        let p = (t / 5.5).truncatingRemainder(dividingBy: 1)
        let ease: Double
        if p < 0.38 {                                   // in
            let u = p / 0.38
            ease = u * u * (3 - 2 * u)
        } else {                                        // out, longer
            let u = (p - 0.38) / 0.62
            ease = 1 - u * u * (3 - 2 * u)
        }
        return 1 + 0.085 * m.breath * (ease - 0.5) * 2
    }

    /// The wave running through her surface: inward while she listens,
    /// outward while she speaks, nothing while she waits. `u` is where you
    /// are on the sphere, 0 at one pole and 1 at the other.
    private func flow(_ u: Double, _ t: Double, _ a: Double) -> Double {
        guard m.flow != 0 else { return 0 }
        // 0.30 tore the rings off the sphere at a real level (checked in the
        // simulator at 0.62): it has to read as a wave through her, not as
        // her coming apart.
        return sin(u * 6 - t * 4.5 * m.flow) * a * 0.15 * m.flow
    }

    /// Working: a segment slips off its line for a frame or two.
    private func jitter(_ k: Int, _ t: Double, _ w: Double) -> Double {
        guard m.jitter > 0 else { return 0 }
        let seed = sin(Double(k) * 41.7 + (t * 7).rounded(.down)) 
        return (seed - seed.rounded(.down) - 0.5) * w * 0.05
    }

    /// The sphere, turned and tipped, flattened onto the screen.
    private func project(_ x: Double, _ y: Double, _ z: Double,
                         _ ry: Double, _ rx: Double, _ r: Double) -> (Double, Double, Double) {
        let x1 = x * cos(ry) - z * sin(ry)
        var z1 = x * sin(ry) + z * cos(ry)
        let y1 = y * cos(rx) - z1 * sin(rx)
        z1 = y * sin(rx) + z1 * cos(rx)
        let f = 1 / (1.9 - z1 / (r * 0.9))
        return (x1 * f, y1 * f, z1)
    }

    private func ring(_ points: [(Double, Double)], closed: Bool = true) -> Path {
        var p = Path()
        for (i, pt) in points.enumerated() {
            i == 0 ? p.move(to: CGPoint(x: pt.0, y: pt.1)) : p.addLine(to: CGPoint(x: pt.0, y: pt.1))
        }
        if closed { p.closeSubpath() }
        return p
    }

    /// Bloom. A stroke drawn once through a shadow filter and once plain --
    /// the lit ring in skin.css is the same trick.
    private func glow(_ ctx: inout GraphicsContext, _ w: Double, _ color: Color,
                      _ body: (inout GraphicsContext) -> Void) {
        var lit = ctx
        lit.addFilter(.shadow(color: color.opacity(0.85 * m.bloom),
                              radius: w * 0.035 * m.bloom))
        body(&lit)
        body(&ctx)
    }

    private func vignette(_ ctx: GraphicsContext, w: Double) {
        let r = CGRect(x: -w, y: -w, width: w * 2, height: w * 2)
        ctx.fill(Path(r), with: .radialGradient(
            Gradient(colors: [.clear, Color(red: 0.012, green: 0.008, blue: 0.031).opacity(0.85)]),
            center: .zero, startRadius: w * 0.18, endRadius: w * 0.62))
    }

    private func scanlines(_ ctx: GraphicsContext, w: Double) {
        var p = Path()
        var y = -w
        while y < w { p.addRect(CGRect(x: -w, y: y, width: w * 2, height: 1)); y += 3 }
        ctx.fill(p, with: .color(.black.opacity(0.20)))
    }

    // ---------------------------------------------------------------- draws

    private func draw(_ ctx: GraphicsContext, w: Double, t: Double) {
        var c = ctx
        switch style {
        case .portrait, .halo: halo(&c, w, t)
        case .bubble:          bubble(&c, w, t)
        case .groove:          groove(&c, w, t)
        case .trail:           trail(&c, w, t)
        case .ribbon:          ribbon(&c, w, t)
        case .ring:            ring(&c, w, t)
        case .liquid:          liquid(&c, w, t)
        case .lissajous:       lissajous(&c, w, t)
        case .bubbles:         bubbles(&c, w, t)
        case .aurora:          aurora(&c, w, t)
        }
    }

    /// Lit rings around a globe, the magenta one at her equator.
    private func halo(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.30 * breath(t), ry = t * m.spin * 3, rx = sin(t * 0.3) * 0.35
        for k in 0..<12 {                               // meridians, faint
            let lon = Double(k) / 12 * .pi * 2
            let pts = (0...60).map { i -> (Double, Double) in
                let lat = (Double(i) / 60 - 0.5) * .pi
                let p = project(cos(lon) * cos(lat) * R, sin(lat) * R,
                                sin(lon) * cos(lat) * R, ry, rx, R)
                return (p.0, p.1)
            }
            ctx.stroke(ring(pts, closed: false), with: .color(tint.opacity(0.10)), lineWidth: 1)
        }
        for k in 0..<9 {
            let lat = (Double(k) / 8 - 0.5) * .pi * 0.92
            let cr = cos(lat) * R, cy = sin(lat) * R
            let pts = (0...90).map { i -> (Double, Double) in
                let lon = Double(i) / 90 * .pi * 2
                let wob = 1 + a * 0.14 * m.depth * sin(lon * 4 + t * m.wobble + Double(k))
                    + flow(Double(k) / 8, t, a)
                let p = project(cos(lon) * cr * wob, cy * wob, sin(lon) * cr * wob, ry, rx, R)
                return (p.0 + jitter(k, t, w), p.1)
            }
            let col = k == 4 ? mag : tint
            let o = 0.25 + 0.55 * (1 - abs(Double(k) - 4) / 5)
            glow(&ctx, w, col) { g in
                g.stroke(ring(pts), with: .color(col.opacity(o)), lineWidth: w * 0.006)
            }
        }
    }

    /// Glass shells with a specular and a rim, added together.
    private func bubble(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.26 * breath(t)
        var add = ctx
        add.blendMode = .plusLighter
        for i in 0..<5 {
            let an = t * m.spin * 2.4 + Double(i) * 1.25
            let off = R * (0.10 + a * 0.30 * m.depth + flow(Double(i) / 5, t, a) * 0.5)
            let x = cos(an) * off, y = sin(an * 1.2) * off * 0.7
            let rr = R * (0.85 + 0.12 * sin(t * m.wobble * 0.4 + Double(i)))
            let hue = i % 2 == 0 ? tint : mag
            let rect = CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)
            add.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [
                    .init(color: hue.opacity(0.30 + a * 0.25), location: 0),
                    .init(color: hue.opacity(0.06), location: 0.55),
                    .init(color: hue.opacity(0.26 + a * 0.30), location: 0.92),
                    .init(color: hue.opacity(0), location: 1)]),
                center: CGPoint(x: x - rr * 0.3, y: y - rr * 0.35),
                startRadius: rr * 0.05, endRadius: rr))
        }
    }

    /// The record, wrapped around a globe.
    private func groove(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.30 * breath(t), ry = t * m.spin * 2.2, rx = 0.30 + sin(t * 0.25) * 0.2
        for k in 0..<26 {
            let lat = (Double(k) / 25 - 0.5) * .pi * 0.96
            let cr = cos(lat) * R, cy = sin(lat) * R
            let pts = (0...100).map { i -> (Double, Double) in
                let lon = Double(i) / 100 * .pi * 2
                let d = 1 + sin(lon * 3 + t * m.wobble + Double(k) * 0.35) * a * 0.10 * m.depth
                    + flow(Double(k) / 25, t, a)
                let p = project(cos(lon) * cr * d, cy * d, sin(lon) * cr * d, ry, rx, R)
                return (p.0 + jitter(k, t, w), p.1)
            }
            let col = k % 7 == 0 ? mag : tint
            let o = 0.08 + 0.45 * (0.3 + a) * (1 - abs(Double(k) - 12.5) / 16)
            ctx.stroke(ring(pts), with: .color(col.opacity(o)), lineWidth: w * 0.004)
        }
    }

    /// A light running over the surface, dimming as it passes behind.
    private func trail(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.29 * breath(t), ry = t * m.spin * 2.5, rx = 0.25
        for k in 0..<10 {                               // the cage it runs on
            let lon = Double(k) / 10 * .pi * 2
            let pts = (0...50).map { i -> (Double, Double) in
                let lat = (Double(i) / 50 - 0.5) * .pi
                let p = project(cos(lon) * cos(lat) * R, sin(lat) * R,
                                sin(lon) * cos(lat) * R, ry, rx, R)
                return (p.0, p.1)
            }
            ctx.stroke(ring(pts, closed: false), with: .color(tint.opacity(0.07)), lineWidth: 1)
        }
        let n = 150
        for i in 0..<n {
            let u = t * (0.5 + m.wobble * 0.35) - Double(i) * 0.012
            let lat = sin(u * 0.9) * 1.25, lon = u * 2.1
            let rr = R * (1 + a * 0.10 * m.depth * sin(u * 4)
                          + flow(Double(i) / Double(n), t, a) * 0.6)
            let p = project(cos(lon) * cos(lat) * rr, sin(lat) * rr,
                            sin(lon) * cos(lat) * rr, ry, rx, R)
            let front = (p.2 / R + 1) / 2, fade = 1 - Double(i) / Double(n)
            let dot = w * 0.009 * fade + w * 0.002
            let rect = CGRect(x: p.0 - dot, y: p.1 - dot, width: dot * 2, height: dot * 2)
            ctx.fill(Path(ellipseIn: rect),
                     with: .color((i < 12 ? mag : tint)
                        .opacity(fade * (0.15 + 0.75 * front) * (0.4 + a))))
        }
    }

    /// The lissajous, wrapped on a shell, with her core inside it.
    private func ribbon(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.29 * breath(t), ry = t * m.spin * 2.8, rx = sin(t * 0.22) * 0.4
        for s in 0..<3 {
            let pts = (0...420).map { i -> (Double, Double) in
                let u = Double(i) / 420 * .pi * 2
                let lat = sin(u * Double(2 + s)) * 1.2
                let lon = u * 3 + Double(s) * 2.1 + t * 0.2
                let rr = R * (0.92 + a * 0.16 * m.depth * sin(u * 6 + t * m.wobble)
                              + flow(u / (.pi * 2), t, a))
                let p = project(cos(lon) * cos(lat) * rr, sin(lat) * rr,
                                sin(lon) * cos(lat) * rr, ry, rx, R)
                return (p.0, p.1)
            }
            let col = s == 1 ? mag : tint
            glow(&ctx, w, col) { g in
                g.stroke(ring(pts, closed: false),
                         with: .color(col.opacity(0.55 - Double(s) * 0.12)),
                         lineWidth: w * 0.005)
            }
        }
        let core = R * 0.16 * (1 + a * 0.5 * m.depth)
        glow(&ctx, w, tint) { g in
            g.fill(Path(ellipseIn: CGRect(x: -core, y: -core, width: core * 2, height: core * 2)),
                   with: .color(tint.opacity(0.5 + a * 0.4)))
        }
    }

    // ------------------------------------------------------- the flat five

    /// One lit ring with a soft core: the whole state in a single shape,
    /// which is what makes it readable from the sofa.
    private func ring(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.29 * breath(t) * (1 + a * 0.12 * m.depth)
        glow(&ctx, w, tint) { g in
            g.stroke(Path(ellipseIn: CGRect(x: -R, y: -R, width: R * 2, height: R * 2)),
                     with: .color(tint.opacity(0.85)),
                     lineWidth: w * 0.018 * (1 + a * 0.9 * m.depth))
        }
        let halo = R * 1.5
        ctx.fill(Path(ellipseIn: CGRect(x: -halo, y: -halo, width: halo * 2, height: halo * 2)),
                 with: .radialGradient(
                    Gradient(colors: [tint.opacity(0.16 + a * 0.2 * m.bloom), tint.opacity(0)]),
                    center: .zero, startRadius: 0, endRadius: halo))
        // A second, thinner ring carries the flow, so listening and speaking
        // are told apart on a shape that has nothing else to move.
        if m.flow != 0 {
            let r2 = R * (0.62 + flow(0.5, t, a) * 2)
            ctx.stroke(Path(ellipseIn: CGRect(x: -r2, y: -r2, width: r2 * 2, height: r2 * 2)),
                       with: .color(mag.opacity(0.55)), lineWidth: w * 0.006)
        }
    }

    /// A drop of her, holding its own shape against the noise.
    private func liquid(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.30 * breath(t)
        var p = Path()
        for i in 0...180 {
            let an = Double(i) / 180 * .pi * 2
            let n = sin(an * 3 + t * m.wobble * 0.4) * 0.5
                  + sin(an * 5 - t * m.wobble * 0.6) * 0.3
                  + sin(an * 2 + t * 0.7) * 0.4
            let r = R * (1 + n * a * 0.45 * m.depth + flow(an / (.pi * 2), t, a))
            let pt = CGPoint(x: cos(an) * r, y: sin(an) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        ctx.fill(p, with: .radialGradient(
            Gradient(colors: [tint.opacity(0.55), tint.opacity(0.05)]),
            center: .zero, startRadius: R * 0.1, endRadius: R * 1.3))
        glow(&ctx, w, tint) { g in
            g.stroke(p, with: .color(tint.opacity(0.9)), lineWidth: w * 0.005)
        }
    }

    /// Ribbons crossing, in two colours: the shape that reads as thinking
    /// even before the colour says so.
    private func lissajous(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.33 * breath(t)
        for k in 0..<5 {
            let pts = (0...240).map { i -> (Double, Double) in
                let u = Double(i) / 240 * .pi * 2
                let scale = R * (0.6 + a * 0.5 * m.depth)
                return (sin(u * (2 + Double(k) * 0.1) + t * m.spin * 3) * scale,
                        sin(u * 3 + t * (0.35 + m.spin) + Double(k) * 0.6) * scale)
            }
            let col = k % 2 == 1 ? mag : tint
            ctx.stroke(ring(pts, closed: false),
                       with: .color(col.opacity(0.12 + 0.4 * (1 - Double(k) / 5))),
                       lineWidth: w * 0.004)
        }
    }

    /// Glass shells, flat: the softest of them, and the one that does least
    /// when she is quiet.
    private func bubbles(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.30 * breath(t)
        var add = ctx
        add.blendMode = .plusLighter
        for i in 0..<5 {
            let an = t * (0.5 + m.spin) + Double(i) * 1.26
            let off = R * (0.12 + a * 0.34 * m.depth + flow(Double(i) / 5, t, a))
            let x = cos(an) * off, y = sin(an * 1.3) * off
            let hue = i % 2 == 0 ? tint : mag
            let rect = CGRect(x: x - R, y: y - R, width: R * 2, height: R * 2)
            add.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [
                    .init(color: hue.opacity(0.02), location: 0),
                    .init(color: hue.opacity(0.22 + a * 0.2), location: 0.75),
                    .init(color: hue.opacity(0), location: 1)]),
                center: CGPoint(x: x, y: y), startRadius: R * 0.2, endRadius: R))
        }
    }

    /// Curtains of light across a disc. Strokes, not filled bands: filled
    /// ones stacked into a solid muddy shape (checked in the simulator,
    /// 2026-09-29), and an aurora is light you can see through.
    private func aurora(_ ctx: inout GraphicsContext, _ w: Double, _ t: Double) {
        let a = amp(t)
        let R = w * 0.34 * breath(t)
        var disc = ctx
        disc.clip(to: Path(ellipseIn: CGRect(x: -R, y: -R, width: R * 2, height: R * 2)))
        disc.blendMode = .plusLighter
        for k in 0..<6 {
            let base = (Double(k) - 2.5) * R * 0.28
            var curtain = Path()
            for i in 0...70 {
                let x = -R * 1.1 + Double(i) / 70 * R * 2.2
                let y = base
                    + sin(x * 0.014 + t * (0.5 + m.wobble * 0.22) + Double(k) * 1.1)
                        * R * 0.18 * (0.35 + a * 1.1 * m.depth)
                    + flow(Double(k) / 6, t, a) * R * 0.8
                let pt = CGPoint(x: x, y: y)
                i == 0 ? curtain.move(to: pt) : curtain.addLine(to: pt)
            }
            let col = k % 2 == 1 ? mag : tint
            var soft = disc
            soft.addFilter(.blur(radius: R * 0.09))
            soft.stroke(curtain, with: .color(col.opacity(0.16 + a * 0.16 * m.bloom)),
                        lineWidth: R * 0.13)
            disc.stroke(curtain, with: .color(col.opacity(0.10 + a * 0.10)),
                        lineWidth: R * 0.03)
        }
    }
}

/// A face, small, moving, to choose from. The picker was a list of words and
/// none of them told him what he was choosing (Oscar, 2026-09-29); each tile
/// cycles the four states so the colour and the movement are both on show.
struct FacePreview: View {
    let style: FaceStyle
    var side: CGFloat = 92

    @State private var step = 0
    private static let states: [(VoiceState, Color)] = [
        (.idle,      Color(red: 0.50, green: 0.55, blue: 1.0)),
        (.listening, Color(red: 0.30, green: 1.0, blue: 0.50)),
        (.thinking,  Color(red: 1.0, green: 0.22, blue: 0.78)),
        (.speaking,  Color(red: 0.27, green: 0.90, blue: 0.97)),
    ]
    private let clock = Timer.publish(every: 2.4, on: .main, in: .common).autoconnect()

    var body: some View {
        let (state, tint) = Self.states[step % Self.states.count]
        return ZStack {
            Skin.void
            if style == .portrait {
                Image(systemName: "person.crop.square")
                    .font(.system(size: side * 0.42, weight: .thin))
                    .foregroundStyle(Skin.cyan.opacity(0.7))
            } else {
                // A level she never actually holds, so a still glance shows
                // the shape at work rather than at rest.
                VoiceVisual(style: style, state: state, amplitude: 0.55, tint: tint)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Skin.radius))
        .onReceive(clock) { _ in step += 1 }
    }
}
