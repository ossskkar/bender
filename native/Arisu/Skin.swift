import SwiftUI

/// One look for the whole app.
///
/// The deck grew up as its own screen and kept its own colours, corners and
/// type; the chat arrived from a web page with a third set. Every surface
/// reads from here now (Oscar, 2026-09-28), and the values are lain's skin
/// (`skin.css`) so the iPad and the dashboard are recognisably one thing.
enum Skin {
    /// `--cyan`: her, and anything that is on.
    static let cyan = Color(red: 0.27, green: 0.90, blue: 0.97)      // #45E5F7
    /// `--mag`: him, her name, and anything being edited. Lifted from
    /// #FF3D8A on 2026-09-29: on the iPad at full brightness the darker
    /// magenta on near-black was hard to read across the desk.
    static let mag = Color(red: 1.0, green: 0.36, blue: 0.62)        // #FF5C9E
    /// `--ink`: writing that is not either of them. Also lifted, for the
    /// same reason -- labels at #7E8FB8 were grey on black.
    static let ink = Color(red: 0.64, green: 0.71, blue: 0.85)       // #A3B5D9
    /// `--void`: the room behind everything.
    static let void = Color(red: 0.02, green: 0.02, blue: 0.05)      // #06050C
    /// Off. Colour means on and grey means off, everywhere.
    static let off = Color.white.opacity(0.45)
    /// A record light, the one colour that is not part of the hologram. It is
    /// also what a failed press wears, for the same reason: it must not read
    /// as a mood.
    static let recording = Color(red: 1.0, green: 0.27, blue: 0.31)
    /// It worked. The same green the room wears while it is hearing him, so
    /// the app has one "yes" colour and not two.
    static let good = Color(red: 0.30, green: 1.0, blue: 0.50)
    /// Text on a filled control.
    static let onLit = Color(red: 0.02, green: 0.04, blue: 0.08)

    /// Free form (Oscar, 2026-10-01): no box, edge, bracket or grid line on
    /// any control -- only the words, the icons and her, with smoke.
    static let freeFormKey = "arisu.freeForm"
    /// How much smoke free form draws round her; 0 is none, 1 the default.
    static let smokeKey = "arisu.smoke"

    /// The fill of anything raised off the void: a key, a bubble, a bar.
    static let raised = Color.white.opacity(0.08)
    /// One corner radius, and it is none: the Record panel's square neon
    /// boxes became the whole app's look (Oscar, 2026-09-30).
    static let radius: CGFloat = 0

    /// Everything is typed in the same face. She is a terminal.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// A small caps heading: "DECK", the legend, the labels on the sheets.
    static func caption(_ text: String, _ tint: Color) -> some View {
        Text(text.uppercased())
            .font(mono(12, .semibold))
            .tracking(3)
            .foregroundStyle(tint)
    }
}

/// A panel: the key, the bubble, the answer strip, the composer's field.
/// Drawn only outside free form: every box, edge and lit bar goes through it.
struct Edge<V: View>: View {
    @AppStorage(Skin.freeFormKey) private var free = false
    let v: V
    init(@ViewBuilder _ v: () -> V) { self.v = v() }
    var body: some View { if !free { v } }
}

struct Raised: ViewModifier {
    var tint: Color = Skin.cyan
    var stroke: Double = 0.3
    var fill: Color = Skin.raised
    func body(content: Content) -> some View {
        content
            .plate { RoundedRectangle(cornerRadius: Skin.radius).fill(fill) }
            .edge { RoundedRectangle(cornerRadius: Skin.radius).stroke(tint.opacity(stroke)) }
            // A lit edge glows; a quiet one does not, or every box would shout.
            .shadow(color: stroke >= 0.6 ? tint.opacity(0.6) : .clear, radius: 5)
    }
}

extension View {
    /// An outline or bar over a control; gone in free form.
    func edge<V: View>(alignment: Alignment = .center, @ViewBuilder _ v: () -> V) -> some View {
        overlay(alignment: alignment) { Edge(v) }
    }

    /// A control's box behind it; gone in free form.
    func plate<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        background { Edge(v) }
    }

    /// A panel in the Record panel's style: grid and scanlines behind, neon
    /// corner brackets over the top.
    func console(_ grid: Color = Skin.cyan, brackets: Color = Skin.mag) -> some View {
        background(Grid(tint: grid)).overlay(Brackets(tint: brackets))
    }

    func raised(_ tint: Color = Skin.cyan, stroke: Double = 0.3,
                fill: Color = Skin.raised) -> some View {
        modifier(Raised(tint: tint, stroke: stroke, fill: fill))
    }
}

/// The one icon button. The top row, the composer and the sheets all drew
/// their own before this -- three sizes and three corner radii in one screen.
struct IconButton: View {
    let symbol: String
    let label: String
    var tint: Color = Skin.cyan
    var lit = false
    var stroke = 0.35
    /// The icon's own colour, when it should not be the edge's (the title bar).
    var ink: Color? = nil
    let action: () -> Void
    @AppStorage(Skin.freeFormKey) private var free = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                // Lit with no box to fill: the icon itself carries the colour.
                .foregroundStyle(lit ? (free ? tint : Skin.onLit) : ink ?? tint)
                .frame(width: 48, height: 40)
                .raised(tint, stroke: lit ? 0 : stroke,
                        fill: lit ? tint : Color.black.opacity(0.35))
        }
        .accessibilityLabel(label)
    }
}

/// A faint neon grid with scanlines, behind the panel (and the deck below it).
struct Grid: View {
    let tint: Color
    @AppStorage(Skin.freeFormKey) private var free = false
    var body: some View {
        Canvas { ctx, size in
            guard !free else { return }
            var grid = Path()
            for x in stride(from: 0, through: size.width, by: 28) {
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 28) {
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(tint.opacity(0.07)), lineWidth: 1)
            for y in stride(from: 0, through: size.height, by: 3) {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(.black.opacity(0.25)))
            }
        }
        // Clear in free form, so her animation behind the controls shows.
        .background(free ? Color.clear : Color.black)
    }
}

/// Neon corner brackets instead of a box.
struct Brackets: View {
    let tint: Color
    var body: some View {
        Edge { GeometryReader { g in
            let w = g.size.width, h = g.size.height, l: CGFloat = 22
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: w, y: h - l)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - l, y: h))
                p.move(to: CGPoint(x: l, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(tint, lineWidth: 2)
            .shadow(color: tint, radius: 5)
        } }
        .allowsHitTesting(false)
    }
}

/// Who said a line, in front of it everywhere a conversation is shown
/// (Oscar, 2026-10-01).
func speaker(_ mine: Bool) -> String { mine ? "Oscar> " : "Arisu> " }
