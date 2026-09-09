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
    @State private var showSettings = false

    /// The colour of work being done. Deliberately not one of the moods --
    /// nothing she ever *is* looks like this, so it reads as a state and not
    /// as a feeling.
    private let working = Color(red: 1.0, green: 0.22, blue: 0.78)

    /// What she says, always. The mood still tints the room around her, but
    /// the words themselves stay one colour -- "hot" rendered them at
    /// (1.0, 0.30, 0.42), which reads as magenta and collided with the
    /// magenta the meter now uses to mean she is working.
    private let voice = Color(red: 0.27, green: 0.90, blue: 0.97)

    /// Recording red. The one colour on this screen that is not part of the
    /// hologram's palette, on purpose: a record light should look like a
    /// record light and not like a mood.
    private let recording = Color(red: 1.0, green: 0.27, blue: 0.31)

    /// His voice, and the colour his words are already written in. The meter
    /// borrows it so that "who is making this move" needs no legend: the bars
    /// are the colour of whoever's caption is on screen.
    private let listener = Color.white

    /// Who is doing something, right now. Exactly one of them, because two
    /// things lighting up at once is what made the old meter unreadable --
    /// it moved for his microphone whether he was talking, she was talking,
    /// or nothing was happening at all.
    private enum Phase { case idle, listening, thinking, speaking }

    private var phase: Phase {
        // The whisper path has no duplex: it knows it is working and nothing
        // else, so its only two states are working and not.
        if pet.mode == .whisper { return pet.thinking ? .thinking : .idle }
        if live.pushing { return .listening }
        if live.thinking { return .thinking }
        if live.speaking { return .speaking }
        if live.hearing { return .listening }
        return .idle
    }

    private var phaseColor: Color {
        switch phase {
        case .thinking:  return working
        case .speaking:  return voice
        case .listening: return listener
        case .idle:      return glow
        }
    }

    private var phaseLabel: String? {
        switch phase {
        case .thinking:  return "thinking"
        case .speaking:  return "arisu"
        case .listening: return "you"
        case .idle:      return nil
        }
    }

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
                // The ground under her carries the same colour as the meter,
                // so the state is readable from across the room, where the
                // twenty bars are not.
                RadialGradient(colors: [phaseColor.opacity(0.24),
                                        phaseColor.opacity(0.06), .clear],
                               center: .center, startRadius: 4, endRadius: reach * 0.75)
                    .animation(.easeInOut(duration: 0.35), value: phaseColor)

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
        .animation(.easeInOut(duration: 0.25), value: live.thinking)
        .animation(.easeInOut(duration: 0.25), value: pet.running)
        .onAppear {
            // Only if she was left running: coming back to the app should not
            // undo a stop.
            if pet.running { pet.begin() }
            withAnimation(.easeInOut(duration: 4.3).repeatForever(autoreverses: true)) { drift = true }
            withAnimation(.linear(duration: 5.6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }

    /// Off. Colour means on and grey means off everywhere on this screen --
    /// before, the pause button went magenta when it was *stopped*, which made
    /// the loudest thing on screen the thing that was doing nothing.
    private let off = Color.white.opacity(0.3)

    /// The workbench controls, stacked up the right edge. Three times the size
    /// they were, because he reaches for them from across the desk and one of
    /// them is held rather than tapped -- a 28pt target for push-to-talk is a
    /// target you miss mid-sentence.
    ///
    /// The model picker is gone. It cycled mini, full and whisper, and two of
    /// those are no longer choices anyone makes: the desk decides which
    /// realtime model to spend on at mint time, and whisper is the old path.
    private var controls: some View {
        VStack(spacing: 16) {
            iconButton(showTranscript ? "text.bubble.fill" : "text.bubble",
                       tint: showTranscript ? glow : off) {
                showTranscript.toggle()
            }
            // Conversation, not transport: this is whether the two of them are
            // talking at all. A voice in a circle rather than a pause bar --
            // his choice, 2026-09-09, and the right one: speech bubbles read
            // as messages, and nothing here is typed.
            iconButton(pet.running ? "waveform.circle.fill" : "waveform.circle",
                       tint: pet.running ? glow : off) {
                pet.toggleRunning()
            }
            talkButton
            iconButton("slider.horizontal.3", tint: off) {
                showSettings = true
            }
        }
        .padding(.trailing, 26)
        .padding(.bottom, 26)
        .sheet(isPresented: $showSettings) { SettingsSheet(live: live) }
    }

    /// Hold to say something long.
    ///
    /// Two states in one control, because they are the same idea: off, the mic
    /// is open and she answers when she thinks he has finished; on, nothing
    /// reaches her until this is held, and letting go ends the turn. A tap
    /// switches modes, a press-and-hold is the turn itself.
    ///
    /// A record dot rather than a microphone, because a microphone glyph is
    /// what the *other* button already means -- whether she can hear the room
    /// at all. This one is about capturing one thing he chooses to say, which
    /// is what a record button has meant on every device he has ever owned.
    private var talkButton: some View {
        let armed = live.turnMode
        let symbol = armed ? "record.circle.fill" : "record.circle"
        let tint: Color = live.pushing ? recording : (armed ? glow : off)
        return Image(systemName: symbol)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 46, height: 40)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(Capsule().fill(live.pushing ? recording.opacity(0.2)
                                                    : .black.opacity(0.35)))
            .overlay(Capsule().stroke(tint.opacity(live.pushing ? 0.9 : 0.28),
                                      lineWidth: live.pushing ? 2 : 1))
            .scaleEffect(live.pushing ? 1.06 : 1)
            .contentShape(Capsule())
            .onTapGesture { live.turnMode.toggle() }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if armed { live.startTurn() } }
                    .onEnded { _ in live.endTurn() })
            .animation(.easeOut(duration: 0.12), value: live.pushing)
    }

    private func iconButton(_ symbol: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 46, height: 40)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
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
        VStack(spacing: 7) {
            Group {
                switch phase {
                // Thinking and speaking are both things happening off-screen
                // with no signal to plot, so both are the same travelling
                // wave; only the colour separates them. Listening plots his
                // actual microphone, because there the signal exists.
                case .thinking, .speaking: wave(phaseColor)
                case .listening, .idle:    level_meter
                }
            }
            .frame(height: 16)
            if let phaseLabel {
                Text(phaseLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(phaseColor.opacity(0.85))
                    .shadow(color: phaseColor.opacity(0.6), radius: 6)
                    .transition(.opacity)
            } else {
                // Held open, so the meter does not hop up and down the screen
                // every time one of them stops talking.
                Color.clear.frame(height: 13)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phaseLabel)
    }

    private var level_meter: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                let lit = Float(i) / 20 < pet.level
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? (i > 16 ? Color.pink : phaseColor)
                              : Color.white.opacity(0.12))
                    .frame(width: 5, height: 10)
            }
        }
        .shadow(color: phase == .listening ? phaseColor.opacity(0.5) : .clear,
                radius: 7)
        .animation(.easeOut(duration: 0.12), value: pet.level)
    }

    /// A wave running left to right. `TimelineView` drives it off the frame
    /// clock rather than an animation on a `@State` flag: twenty bars each
    /// with their own phase is exactly the shape SwiftUI's implicit
    /// animation cannot express.
    private func wave(_ tint: Color) -> some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // She speaks faster than she thinks, and the bars should say so
            // before the colour does.
            let speed = phase == .speaking ? 1.5 : 0.85
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    let offset = Double(i) / 20 - t * speed
                    let w = (sin(offset * .pi * 2) + 1) / 2
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tint.opacity(0.18 + w * 0.82))
                        .frame(width: 5, height: 4 + w * 12)
                }
            }
            .shadow(color: tint.opacity(0.7), radius: 8)
        }
    }
}
