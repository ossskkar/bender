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
    /// `--mag`: him, her name, and anything being edited.
    static let mag = Color(red: 1.0, green: 0.24, blue: 0.54)        // #FF3D8A
    /// `--ink`: writing that is not either of them.
    static let ink = Color(red: 0.49, green: 0.56, blue: 0.72)       // #7E8FB8
    /// `--void`: the room behind everything.
    static let void = Color(red: 0.02, green: 0.02, blue: 0.05)      // #06050C
    /// Off. Colour means on and grey means off, everywhere.
    static let off = Color.white.opacity(0.3)
    /// A record light, the one colour that is not part of the hologram. It is
    /// also what a failed press wears, for the same reason: it must not read
    /// as a mood.
    static let recording = Color(red: 1.0, green: 0.27, blue: 0.31)
    /// It worked. The same green the room wears while it is hearing him, so
    /// the app has one "yes" colour and not two.
    static let good = Color(red: 0.30, green: 1.0, blue: 0.50)
    /// Text on a filled control.
    static let onLit = Color(red: 0.02, green: 0.04, blue: 0.08)

    /// The fill of anything raised off the void: a key, a bubble, a bar.
    static let raised = Color.white.opacity(0.05)
    /// One corner radius. Three of them was the loudest thing about the old
    /// screen without anyone being able to say why.
    static let radius: CGFloat = 10

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
struct Raised: ViewModifier {
    var tint: Color = Skin.cyan
    var stroke: Double = 0.3
    var fill: Color = Skin.raised
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Skin.radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Skin.radius).stroke(tint.opacity(stroke)))
    }
}

extension View {
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(lit ? Skin.onLit : tint)
                .frame(width: 48, height: 40)
                .raised(tint, stroke: lit ? 0 : 0.35,
                        fill: lit ? tint : Color.black.opacity(0.35))
        }
        .accessibilityLabel(label)
    }
}
