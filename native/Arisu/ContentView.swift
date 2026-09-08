import SwiftUI

/// The hologram. Three stacked copies of the same face -- one solid, two
/// colour-split ghosts that drift -- plus scanlines and a sweep.
///
/// The web version drew this with a `filter: drop-shadow` wrapping the whole
/// group, which forced Safari to flatten and re-blur every layer on every
/// frame. Here the glow is a shadow the compositor caches, and the drift is a
/// plain animation on two image layers, so nothing is rasterised per frame.
struct ContentView: View {
    @ObservedObject var pet: Pet
    @ObservedObject var live: Live
    @State private var drift = false
    @State private var sweep = false
    /// Whether the two of them are subtitled. Kept across launches because it
    /// is a preference about the room, not about the conversation -- reading
    /// her from across the desk and watching her from the sofa want different
    /// answers, and neither should reset every morning.
    @AppStorage("arisu.transcript") private var showTranscript = true

    /// The colour of work being done. Deliberately not one of the moods --
    /// nothing she ever *is* looks like this, so it reads as a state and not
    /// as a feeling.
    private let working = Color(red: 1.0, green: 0.22, blue: 0.78)

    /// What she says, always. The mood still tints the room around her, but
    /// the words themselves stay one colour -- "hot" rendered them at
    /// (1.0, 0.30, 0.42), which reads as magenta and collided with the
    /// magenta the meter now uses to mean she is working.
    private let voice = Color(red: 0.27, green: 0.90, blue: 0.97)

    private var glow: Color {
        switch pet.mood {
        case "hot":   return Color(red: 1.0, green: 0.30, blue: 0.42)
        case "wired": return Color(red: 0.35, green: 0.94, blue: 0.90)
        case "sad":   return Color(red: 0.45, green: 0.60, blue: 0.95)
        default:      return Color(red: 0.27, green: 0.90, blue: 0.97)
        }
    }

    var body: some View {
        GeometryReader { geo in
            // The face is a square tile, so in landscape it can only ever cover
            // the middle. The ground it sits on has to reach the edges by
            // itself -- a fixed radius left unlit corners on the wide screen.
            let reach = max(geo.size.width, geo.size.height)
            ZStack {
                Color.black
                RadialGradient(colors: [glow.opacity(0.24), glow.opacity(0.06), .clear],
                               center: .center, startRadius: 4, endRadius: reach * 0.75)

                face
                scanlines.allowsHitTesting(false)

                VStack {
                    Spacer()
                    if showTranscript { caption }
                    // A meter for a microphone that is down would be a lie.
                    if pet.running { meter.padding(.bottom, 22) }
                    else { Color.clear.frame(height: 16).padding(.bottom, 22) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottomTrailing) { controls }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: pet.thinking)
        .animation(.easeInOut(duration: 0.25), value: pet.running)
        .onAppear {
            // Only if she was left running: coming back to the app should not
            // undo a stop.
            if pet.running { pet.begin() }
            withAnimation(.easeInOut(duration: 4.3).repeatForever(autoreverses: true)) { drift = true }
            withAnimation(.linear(duration: 5.6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }

    /// The three workbench controls, together in the corner. Small and dim on
    /// purpose: they sit on an ornament, and should lose every argument with
    /// the hologram about attention.
    private var controls: some View {
        HStack(spacing: 12) {
            iconButton(showTranscript ? "captions.bubble.fill" : "captions.bubble",
                       tint: showTranscript ? glow : .white.opacity(0.35)) {
                showTranscript.toggle()
            }
            // Magenta while stopped, the colour nothing she *is* ever uses --
            // so "she is not listening" cannot be mistaken for a mood.
            iconButton(pet.running ? "pause.fill" : "play.fill",
                       tint: pet.running ? glow : working) {
                pet.toggleRunning()
            }
            modeButton
        }
        .padding(.trailing, 22)
        .padding(.bottom, 22)
    }

    private func iconButton(_ symbol: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 24)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Capsule().fill(.black.opacity(0.35)))
                .overlay(Capsule().stroke(glow.opacity(0.28), lineWidth: 1))
        }
    }

    /// Which brain she is running on, and a tap to change it.
    private var modeButton: some View {
        Button { pet.cycleMode() } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(pet.mode == .whisper ? Color.white.opacity(0.4)
                                               : (live.connected ? glow : working))
                    .frame(width: 8, height: 8)
                Text(pet.mode.label)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(.black.opacity(0.35)))
            .overlay(Capsule().stroke(glow.opacity(0.28), lineWidth: 1))
        }
    }

    private var face: some View {
        ZStack {
            Image("lain-face-cy").resizable().scaledToFit()
                .opacity(0.34).offset(x: drift ? -9 : -3, y: drift ? -2 : 2)
            Image("lain-face-mg").resizable().scaledToFit()
                .opacity(0.34).offset(x: drift ? 9 : 3, y: drift ? 3 : -2)
            Image("lain-face").resizable().scaledToFit()
                .opacity(0.96)
        }
        .shadow(color: glow.opacity(0.55), radius: 22)
        .mask(LinearGradient(stops: [
            .init(color: .black, location: 0.86),
            .init(color: .black.opacity(0.45), location: 0.95),
            .init(color: .clear, location: 1.0)], startPoint: .top, endPoint: .bottom))
        .padding(.horizontal, -40)
    }

    private var scanlines: some View {
        GeometryReader { geo in
            Path { p in
                var y: CGFloat = 0
                while y < geo.size.height {
                    p.addRect(CGRect(x: 0, y: y, width: geo.size.width, height: 1))
                    y += 3
                }
            }.fill(glow.opacity(0.055))
        }.ignoresSafeArea()
    }

    /// The last thing each of them said, and nothing older. A new line does
    /// not replace the text in place -- changing the `id` makes it a new view,
    /// so the old one fades out as the new one fades in and the two are never
    /// legible at once. Colour is the only thing saying who spoke.
    private var caption: some View {
        VStack(spacing: 6) {
            if !pet.heard.isEmpty {
                Text(pet.heard)
                    .font(.system(size: 22, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .id(pet.heard)
                    .transition(.opacity)
            }
            if !pet.line.isEmpty {
                Text(pet.line)
                    .font(.system(size: 22, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(voice)
                    .shadow(color: voice.opacity(0.5), radius: 12)
                    .id(pet.line)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: pet.heard)
        .animation(.easeInOut(duration: 0.45), value: pet.line)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
    }

    /// The same twenty bars all the way through, because a second widget
    /// appearing elsewhere on the screen was the thing that made her look
    /// busy in a different place from where she listens. Working is the same
    /// object moving differently, in a colour she is never otherwise.
    private var meter: some View {
        Group {
            if pet.thinking { working_meter } else { level_meter }
        }
        .frame(height: 16)
    }

    private var level_meter: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                let lit = Float(i) / 20 < pet.level
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? (i > 16 ? Color.pink : glow) : Color.white.opacity(0.12))
                    .frame(width: 5, height: 10)
            }
        }
        .animation(.easeOut(duration: 0.12), value: pet.level)
    }

    /// A wave running left to right. `TimelineView` drives it off the frame
    /// clock rather than an animation on a `@State` flag: twenty bars each
    /// with their own phase is exactly the shape SwiftUI's implicit
    /// animation cannot express.
    private var working_meter: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    let phase = Double(i) / 20 - t * 0.85
                    let wave = (sin(phase * .pi * 2) + 1) / 2
                    RoundedRectangle(cornerRadius: 1)
                        .fill(working.opacity(0.18 + wave * 0.82))
                        .frame(width: 5, height: 4 + wave * 12)
                }
            }
            .shadow(color: working.opacity(0.7), radius: 8)
        }
    }
}
