import SwiftUI

/// Breathing exercises (Oscar, 2026-10-08): Calm, Activate and Angry, each
/// with its own rhythm and its own song on the Mac's Spotify. An exercise
/// lasts as long as its song. He asks her out loud ("a calm breathing
/// exercise", "breathe, I'm angry") or presses one under her commands.
///
/// Foundation only down to the marker, so `checks/breathing.py` can compile
/// the real thing without the app.
enum Breath: String, CaseIterable, Identifiable {
    case calm, activate, angry

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// One part of a breath. `to` is how full his lungs are at its end, 0…1,
    /// which is how big she is drawn.
    struct Step { let word: String; let seconds: Double; let to: Double }

    /// Calm: resonance breathing, five breaths a minute, out longer than in.
    /// Activate: a strong breath in, a short one out.
    /// Angry: the physiological sigh -- in, a second short breath on top,
    /// then a long breath out (cyclic sighing, Balban et al. 2023).
    var steps: [Step] {
        switch self {
        case .calm:     return [Step(word: "in", seconds: 4, to: 1),
                                Step(word: "hold", seconds: 2, to: 1),
                                Step(word: "out", seconds: 6, to: 0)]
        case .activate: return [Step(word: "in", seconds: 3, to: 1),
                                Step(word: "out", seconds: 2, to: 0)]
        case .angry:    return [Step(word: "in", seconds: 2, to: 0.75),
                                Step(word: "and in", seconds: 1, to: 1),
                                Step(word: "out slowly", seconds: 6, to: 0)]
        }
    }

    /// The song, as the deck button that plays it on the Mac.
    var songButton: String { "breathe." + rawValue }
    var song: String {
        switch self {
        case .calm:     return "Weightless · Marconi Union"
        case .activate: return "Victory · Two Steps from Hell"
        case .angry:    return "On the Nature of Daylight · Max Richter"
        }
    }
    /// The song's length in seconds, which is the exercise's.
    var duration: Double {
        switch self {
        case .calm: return 480
        case .activate: return 320
        case .angry: return 371
        }
    }

    /// Where he is `elapsed` seconds in: the step, the seconds left in it,
    /// and how full his lungs are, eased.
    func at(_ elapsed: Double) -> (step: Step, left: Double, fill: Double) {
        let cycle = steps.reduce(0) { $0 + $1.seconds }
        var t = elapsed.truncatingRemainder(dividingBy: cycle)
        var from = steps.last!.to
        for s in steps {
            if t < s.seconds {
                let k = t / s.seconds, e = k * k * (3 - 2 * k)
                return (s, s.seconds - t, from + (s.to - from) * e)
            }
            t -= s.seconds
            from = s.to
        }
        return (steps[0], steps[0].seconds, from)
    }

    /// The exercise he asked for, or nil when he did not ask for one. A
    /// breathing word and a kind, or "breathing exercise" alone for Calm --
    /// "out of breath after the run" starts nothing.
    static func asked(_ text: String) -> Breath? {
        let t = text.lowercased()
        func has(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        guard has(#"\bbreath(e|es|ing)?\b"#) else { return nil }
        if has(#"\b(angry|anger|mad|furious|frustrat\w*|irritat\w*|pissed)\b"#) { return .angry }
        if has(#"\b(activat\w*|energi\w*|energy|wake me|awake|alert|pump\w*)\b"#) { return .activate }
        if has(#"\b(calm\w*|relax\w*|stress\w*|anxi\w*|unwind)\b"#) { return .calm }
        return has(#"\bbreathing (exercise|session)\b"#) ? .calm : nil
    }
}
// MARK: - end of Breath

extension Breath {
    var tint: Color {
        switch self {
        case .calm: return Skin.cyan
        case .activate: return Color(red: 0.30, green: 1.0, blue: 0.50)
        case .angry: return Skin.mag
        }
    }

    /// Play or stop the song on the Mac, through the deck's fixed buttons.
    static func press(_ id: String) async {
        var r = URLRequest(url: DeckAPI.base.appendingPathComponent("deck/run"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        _ = try? await URLSession.shared.data(for: r)
    }
}

/// The exercise on screen: she grows as he breathes in and shrinks as he
/// breathes out, with the word and the count under her.
struct BreathingView: View {
    let kind: Breath
    let started: Date
    var style: FaceStyle = .ribbon
    var scale = 1.0, bloom = 1.0, smoke = 0.0
    let stop: () -> Void

    var body: some View {
        TimelineView(.animation) { tl in
            let el = tl.date.timeIntervalSince(started)
            let (step, left, fill) = kind.at(el)
            ZStack {
                Color.black.ignoresSafeArea()
                VoiceVisual(style: style, state: .idle, amplitude: 0.12 + 0.3 * fill,
                            tint: kind.tint, scale: scale * (0.7 + 0.5 * fill),
                            bloom: bloom, speed: 0.6, smoke: smoke)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    Spacer()
                    Text(step.word.uppercased())
                        .font(Skin.mono(44, .bold)).tracking(8)
                        .foregroundStyle(kind.tint)
                        .shadow(color: kind.tint.opacity(0.8), radius: 12)
                    Text("\(Int(left.rounded(.up)))")
                        .font(Skin.mono(28, .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(kind.label.uppercased() + " · "
                         + Self.clock(max(0, kind.duration - el)) + " · " + kind.song)
                        .font(Skin.mono(14)).tracking(1.5)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 18)
                        .padding(.bottom, 60)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: stop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, height: 56)
                }
                .accessibilityLabel("Stop the exercise")
                .padding(24)
            }
        }
    }

    private static func clock(_ s: Double) -> String {
        let n = Int(s.rounded(.up))
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}
