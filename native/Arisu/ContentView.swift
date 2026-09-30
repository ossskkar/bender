import SwiftUI
import WebKit

/// The hologram: `FaceView` for her, plus scanlines and a sweep over the top.
///
/// Her face used to be three stacked copies of one still -- a solid and two
/// colour-split ghosts on a slow drift -- which read well from the sofa and
/// did nothing at all in response to her. It is a live renderer now, and the
/// colour-split, the bloom and the soft bottom edge moved inside it. The
/// scanlines and the sweep stayed here because they belong to the room rather
/// than to her, and they still cost nothing per frame.
struct ContentView: View {
    @ObservedObject var pet: Pet
    @ObservedObject var live: Live
    @ObservedObject var room: Room
    @State private var sweep = false
    /// Whether the two of them are subtitled. Kept across launches because it
    /// is a preference about the room, not about the conversation -- reading
    /// her from across the desk and watching her from the sofa want different
    /// answers, and neither should reset every morning.
    @AppStorage("arisu.transcript") private var showTranscript = true
    /// The Live2D face instead of the portrait. Off by default: it loads from
    /// the desk, and the portrait is the face that works with no network.
    @AppStorage("arisu.live2d") private var live2dFace = true
    /// Her face in voice mode: the portrait/Live2D renderer, or one of the
    /// voice visuals. Ribbon by default -- it is the one that reads as her
    /// from across the desk and still shows the level up close.
    @AppStorage("arisu.faceStyle") private var faceStyle = FaceStyle.ribbon.rawValue
    /// Bubbles or terminal lines, for her subtitles here and for the typed
    /// chat alike (Oscar, 2026-09-26). One preference, both screens: the chat
    /// page is told which to draw through its query string.
    /// Bubbles or terminal lines, per mode: her subtitles over the room and
    /// the typed thread are read at different distances, so one preference
    /// for both was the wrong shape (Oscar, 2026-09-29).
    @AppStorage("arisu.bubbles.voice") private var voiceBubbles = true
    @AppStorage("arisu.bubbles.chat") private var chatBubbles = true
    /// How the voice visual is drawn: size, glow, pace.
    @AppStorage("arisu.faceScale") private var faceScale = 1.0
    @AppStorage("arisu.faceBloom") private var faceBloom = 1.0
    @AppStorage("arisu.faceSpeed") private var faceSpeed = 1.0
    /// Where she stands. Screen geometry differs per device and the face is a
    /// square tile in the middle of it, so this is a preference of the device
    /// rather than of the character.
    @AppStorage("arisu.faceX") private var faceX = 0.0
    @AppStorage("arisu.faceY") private var faceY = 0.0
    @State private var showSettings = false
    /// The deck: his Mac's buttons, on the iPad.
    /// The deck rail, on the right of both modes. Up by default and kept across
    /// launches: it was a full screen he had to open until 2026-09-27, which
    /// meant leaving the conversation to press a button on his Mac.
    @AppStorage("arisu.deck") private var deckShown = true
    /// How much of the screen the deck takes. His, by dragging the seam.
    @AppStorage("arisu.deckFraction") private var deckFraction = DeckRail.fraction
    /// Where the fraction was when this drag started -- a drag reports its
    /// whole translation every time, so adding it each frame would run away.
    @State private var dragFrom: Double?
    /// When either of them last said anything out loud. A room nobody is
    /// talking in holds the microphone open and burns a realtime session for
    /// nothing, so it closes itself (Oscar, 2026-09-28).
    @State private var lastSpoke = Date()
    /// The wordmark's flicker: a tube that is not quite well.
    @State private var flicker = 1.0
    /// The typed chat: its own screen, the terminal page lain serves
    /// (arisu/chat.html) full screen over her. Voice and chat are two
    /// separate UIs in one app (Oscar, 2026-09-23).
    @State private var showChat = true
    /// The typed thread. Held here rather than inside the pane so that it
    /// survives switching to her voice and back -- the conversation is one
    /// thing, and re-fetching it every time he speaks would make it blink.
    @StateObject private var chat = Chat()
    /// Open the chat on its history the moment it is shown -- the room's
    /// History button leaves the room and lands there.
    @State private var chatHistory = false
    /// The recent lines of both of them, oldest first, as chat bubbles.
    @State private var messages: [Bubble] = []

    private struct Bubble: Identifiable, Equatable {
        let id = UUID()
        let mine: Bool
        let text: String
    }

    /// What she says, always. The mood still tints the room around her, but
    /// the words themselves stay one colour -- "hot" rendered them at
    /// (1.0, 0.30, 0.42), which reads as magenta and collided with the
    /// magenta the meter once used to mean she is working.
    /// She is white and he is cyan (Oscar, 2026-09-29). Her words are the
    /// thing being read; his are the prompt beside them, and the state colour
    /// is busy saying what she is doing.
    private let voice = Color.white
    /// His chat bubbles: the legend's thinking magenta.
    private let mineColor = Skin.cyan

    /// Recording red. The one colour on this screen that is not part of the
    /// hologram's palette, on purpose: a record light should look like a
    /// record light and not like a mood.
    private let recording = Skin.recording

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
        // A muted microphone cannot be listening, whatever the socket thinks,
        // and the meter must not move as though it were.
        if live.muted && !live.thinking && !live.speaking { return .idle }
        // The whisper path has no duplex: it knows it is working and nothing
        // else, so its only two states are working and not.
        if pet.mode == .whisper { return pet.thinking ? .thinking : .idle }
        if live.pushing { return .listening }
        if live.thinking { return .thinking }
        if live.speaking { return .speaking }
        if live.hearing { return .listening }
        return .idle
    }

    /// One colour per state, the same for every character. The glow around
    /// her, the ground, the meter and its label all wear it, so the state
    /// reads from across the room. Each is a hue she never has otherwise:
    /// indigo waiting, green hearing him, magenta working, cyan talking.
    private var phaseRGB: (Double, Double, Double) { Self.rgb(phase) }

    private static func rgb(_ phase: Phase) -> (Double, Double, Double) {
        switch phase {
        case .idle:      return (0.50, 0.55, 1.0)
        case .listening: return (0.30, 1.0, 0.50)
        case .thinking:  return (1.0, 0.22, 0.78)
        case .speaking:  return (0.27, 0.90, 0.97)
        }
    }

    private var phaseColor: Color {
        let (r, g, b) = phaseRGB
        return Color(red: r, green: g, blue: b)
    }

    /// How strongly the ground under her is lit, per state.

    private var groundLight: Double {
        switch phase {
        // Halved on 2026-09-29: a drawn face carries its own light, and the
        // two together turned the whole screen one colour.
        case .idle:      return 0.03
        case .listening: return 0.06
        case .thinking:  return 0.05
        case .speaking:  return 0.07
        }
    }

    private var glowRGB: (Double, Double, Double) {
        switch pet.mood {
        case "hot":   return (1.0, 0.30, 0.42)
        case "wired": return (0.35, 0.94, 0.90)
        case "sad":   return (0.45, 0.60, 0.95)
        default:      return (0.27, 0.90, 0.97)
        }
    }

    private var glow: Color {
        let (r, g, b) = glowRGB
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        GeometryReader { geo in
            // Her name is the app's, not the conversation's: it sits over the
            // whole window, deck included (Oscar, 2026-09-28). It used to be
            // drawn inside the right-hand pane, which made it look like a
            // label for the chat.
            VStack(spacing: 0) {
                topBar
                HStack(spacing: 0) {
                    if deckShown {
                        // The deck's share, split top and bottom: Record above,
                        // the deck below where his hand is, a quarter of the
                        // screen each at the default half (Oscar, 2026-09-30).
                        VStack(spacing: 0) {
                            RecordPanel { pet.stop() }.frame(maxHeight: .infinity)
                            DeckRail().frame(maxHeight: .infinity)
                        }
                        .frame(width: geo.size.width * deckFraction)
                    // The one piece of her state that reads in both modes: the
                    // room's glow is behind the typed thread, so the seam
                    // carries it. It is also the handle -- 2pt of light with a
                    // 24pt grab area, because a divider he cannot move is a
                    // decision made for him (Oscar, 2026-09-28).
                        seam(total: geo.size.width)
                    }
                    conversation
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        // A page she was asked to show. The desk already decided how it can be
        // shown, so this only draws it.
        .sheet(item: $live.page) { PageSheet(page: $0) { live.page = nil } }
        .sheet(isPresented: $showSettings) { SettingsSheet(pet: pet, live: live) }
        .onChange(of: pet.heard) { _, t in
            lastSpoke = Date(); say(t, mine: true); obey(t); record(t, "heard")
        }
        .onChange(of: pet.line) { _, t in
            lastSpoke = Date(); say(t, mine: false); record(t, "answer")
        }
        .onChange(of: pet.running) { _, on in
            record(on ? "call started" : "call ended", "call")
            // A call she starts herself -- a queued brief on arrival -- is
            // voice, so the screen goes to her rather than staying on the
            // typed thread while she talks (Oscar, 2026-09-30).
            if on && showChat { showChat = false; lastSpoke = Date() }
        }
        .animation(.easeInOut(duration: 0.25), value: pet.thinking)
        .animation(.easeInOut(duration: 0.25), value: live.thinking)
        .animation(.easeInOut(duration: 0.25), value: pet.running)
        .task { await closeQuietRoom() }
        .onAppear {
            Task { await pet.arrive() }
            withAnimation(.linear(duration: 5.6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }

    /// The lit divider, and the handle that moves it. Clamped so neither side
    /// can be dragged away to nothing.
    private func seam(total: CGFloat) -> some View {
        Rectangle().fill(phaseColor.opacity(0.5)).frame(width: 2)
            .animation(.easeInOut(duration: 0.35), value: phaseColor)
            .overlay(Color.clear.frame(width: 24).contentShape(Rectangle()))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let from = dragFrom ?? deckFraction
                        if dragFrom == nil { dragFrom = from }
                        deckFraction = min(0.7, max(0.2, from + drag.translation.width / total))
                    }
                    .onEnded { _ in dragFrom = nil }
            )
    }

    /// Reading or talking, in the same place. Switching is which of these is
    /// drawn -- not a screen that covers the other one, which is what made
    /// changing mode feel like leaving the app (Oscar, 2026-09-27). The page
    /// draws no chrome of its own here: the row along the top is the app's.
    @ViewBuilder private var conversation: some View {
        if showChat {
            ChatPane(chat: chat, phase: phaseColor, openHistory: $chatHistory) { toVoice() }
        } else {
            hologram
        }
    }

    private var hologram: some View {
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
                RadialGradient(colors: [phaseColor.opacity(groundLight),
                                        phaseColor.opacity(groundLight / 4), .clear],
                               center: .center, startRadius: 4, endRadius: reach * 0.75)
                    .animation(.easeInOut(duration: 0.35), value: phaseColor)

                face
                scanlines.allowsHitTesting(false)

                VStack {
                    Spacer()
                    if room.isGroup { company }
                    if showTranscript {
                        HStack {
                            transcript
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 34)
                        .padding(.trailing, 24)
                    }
                    // What she is doing, in words, under her.
                    Text(pet.running ? stateWord : "not listening")
                        .font(Skin.mono(13, .semibold))
                        .tracking(3)
                        .foregroundStyle(pet.running ? phaseColor : Skin.ink)
                        .animation(.easeInOut(duration: 0.25), value: phaseColor)
                        .shadow(color: .black.opacity(0.9), radius: 8)
                        .padding(.bottom, 10)
                    roomBar
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            // Double tap: the conversation on or off. Single tap: the chrome.
            .onTapGesture(count: 2) { pet.toggleRunning() }
        }
    }

    /// Mute, and the way back to the keyboard. Centred under her rather than
    /// in the top row: in voice mode these are the only two things he does,
    /// and his hands are nowhere near the corner of a 13-inch iPad.
    /// The room's bottom bar. The chat's composer, with the room's controls in
    /// it and her level where the text field is (Oscar, 2026-09-29): one bar
    /// in the same place in both modes, so switching does not move the floor.
    private var roomBar: some View {
        HStack(spacing: 10) {
            // The same two the composer has, in the same corner, because
            // "what did we say" and "start again" are things he wants in the
            // room as much as at the keyboard (Oscar, 2026-09-29).
            squareButton("clock", "History", tint: off) {
                toChat()
                chatHistory = true
            }
            squareButton("plus", "New conversation", tint: off) {
                Task { await chat.new() }
                messages.removeAll()
            }
            squareButton(showTranscript ? "text.bubble.fill" : "text.bubble",
                         "Subtitles", tint: showTranscript ? glow : off) {
                showTranscript.toggle()
            }
            // Her level takes the place of what he would be typing. A meter
            // for a microphone that is down would be a lie, so when there is
            // no call it is the state in words instead.
            // The bar keeps only what he presses; what she is doing is drawn
            // under her, where he is already looking (Oscar, 2026-09-29).
            if pet.running { meter.frame(maxWidth: .infinity) }
            else { Color.clear.frame(height: 36).frame(maxWidth: .infinity) }
            squareButton(live.muted || !pet.running ? "mic.slash" : "mic.fill",
                         "Microphone",
                         tint: pet.running && !live.muted ? listener : off) {
                if pet.running { live.muted.toggle() }
            }
            squareButton("keyboard", "Back to the chat", tint: Self.mag) { toChat() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color.white.opacity(0.03))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.08)),
                 alignment: .top)
    }

    /// What she is doing, in a word, for the bar when the meter is off.
    private var stateWord: String {
        switch phase {
        case .idle:      return "waiting"
        case .listening: return "listening"
        case .thinking:  return "thinking"
        case .speaking:  return "speaking"
        }
    }



    /// Off. Colour means on and grey means off everywhere on this screen --
    /// before, the pause button went magenta when it was *stopped*, which made
    /// the loudest thing on screen the thing that was doing nothing.
    private let off = Skin.off

    /// Her name over the room, at the height of the buttons and in the chat
    /// page's own words, so the two screens carry the same masthead at the same
    /// level (Oscar, 2026-09-26). It used to exist only on the chat page, which
    /// made switching mode feel like leaving the app.
    /// The skin's magenta (`--mag`, #FF3D8A), which is the colour the web
    /// wordmark has always been. This screen had it in cyan for a day and it
    /// stopped reading as the same app (Oscar, 2026-09-28).
    private static let mag = Skin.mag

    private var masthead: some View {
        let cyan = Skin.cyan
        // One line, not two: the title row is a row (Oscar, 2026-09-29). The
        // tagline drops out first when the window is narrow, as the
        // dashboard's own wordmark does.
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Arisuへようこそ！")
                // As tall as the button beside it: the title is the other half
                // of that row, not a caption over it (Oscar, 2026-09-29).
                .font(Skin.mono(26, .bold))
                .tracking(4.5)
                .foregroundStyle(Self.mag)
                .shadow(color: Self.mag.opacity(0.7 * flicker), radius: 12)
                .fixedSize()
            Text("PRESENT DAY · PRESENT TIME")
                .font(Skin.mono(11, .medium))
                .tracking(2.8)
                .foregroundStyle(cyan)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .opacity(flicker)
        .shadow(color: .black.opacity(0.85), radius: 4)
        .allowsHitTesting(false)
        .task { await flickerForever() }
    }

    /// A bad tube. It sits still for a few seconds, drops for a frame or two,
    /// sometimes twice, then settles -- the point is that he cannot predict
    /// it, so the interval and the dip are both drawn fresh each time.
    private func flickerForever() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 2600...9000)))
            for _ in 0..<Int.random(in: 1...3) {
                withAnimation(.linear(duration: 0.05)) { flicker = Double.random(in: 0.45...0.75) }
                try? await Task.sleep(for: .milliseconds(Int.random(in: 40...110)))
                withAnimation(.linear(duration: 0.07)) { flicker = 1.0 }
                try? await Task.sleep(for: .milliseconds(Int.random(in: 50...140)))
            }
        }
    }

    /// Everything that is always on screen, in one row at the top: the
    /// masthead, then the voice-only buttons, then the ones both screens share.
    ///
    /// The voice-only four used to be a stack of 52pt icons in the
    /// bottom-right corner, behind a tap that showed and hid them. Two
    /// problems with that: he had to remember the screen was hiding controls at
    /// all, and they looked nothing like the buttons an inch away at the top.
    /// They are the same square button in the same row now (Oscar, 2026-09-26).
    private var topBar: some View {
        let cyan = Color(red: 0.27, green: 0.90, blue: 0.97)
        return HStack(alignment: .top, spacing: 10) {
            masthead
            Spacer(minLength: 12)
            // Is the microphone hot. Its own control since 2026-09-27, because
            // "mode" is no longer a screen he leaves: typing while she is
            // listening is legal now, and so is shutting the room up without
            // ending the conversation. Off when there is no conversation to
            // mute rather than hidden -- a control that comes and goes is one
            // he has to hunt for.
            // Which device is listening. Shown as soon as there is anyone else
            // to hand it to rather than only in a group: hiding it until the
            // mode is switched means the one control he needs to fix a room
            // appears only after the room is already wrong.
            if room.members.count > 1 {
                squareButton(room.isListener ? "ear.fill" : "ear",
                             "Listen here", tint: room.isListener ? listener : off) {
                    room.listenHere()
                }
            }
            squareButton("slider.horizontal.3", "Settings", tint: off) {
                showSettings = true
            }
            // Shared by both screens.
            squareButton("square.grid.3x3.fill", "Deck",
                         tint: deckShown ? glow : off) { deckShown.toggle() }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 22)
        .background(Color.white.opacity(0.05))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Self.mag.opacity(0.35)),
                 alignment: .bottom)
    }

    private func squareButton(_ symbol: String, _ label: String, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        IconButton(symbol: symbol, label: label, tint: tint ?? Skin.cyan, action: action)
    }

    /// Five minutes of silence ends the call and puts the keyboard back. Not
    /// the conversation -- the thread is one thing and survives this; only the
    /// microphone and the realtime session go.
    private func closeQuietRoom() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            if pet.running && !showChat && Date().timeIntervalSince(lastSpoke) > 300 {
                toChat()
            }
        }
    }

    /// Into the room: the chat goes, she is on screen, and the microphone
    /// opens. One press, because "switch mode" and "start talking" were two
    /// presses for one intention (Oscar, 2026-09-28).
    private func toVoice() {
        showChat = false
        lastSpoke = Date()
        live.muted = false
        if !pet.running { pet.toggleRunning() }
    }

    /// Back to the keyboard. The call ends -- leaving her listening to an
    /// empty desk is how the microphone stays hot for an hour -- and whatever
    /// was said out loud joins the typed thread.
    private func toChat() {
        if pet.running { pet.toggleRunning() }
        showChat = true
        Task { await chat.load() }
    }



    /// The renderer's own vocabulary. `Phase` already says all of it except
    /// asleep, which is not a phase of a conversation but the absence of one:
    /// the microphone is down and there is nothing to be idle about.
    /// The same four states the legend and the glow use, for the sphere.
    private var voiceState: VoiceState {
        switch phase {
        case .idle:      return .idle
        case .listening: return .listening
        case .thinking:  return .thinking
        case .speaking:  return .speaking
        }
    }

    private var faceState: String {
        // Muted is not asleep: she still thinks and speaks what was asked
        // before the mute; `phase` already keeps her from looking like she is
        // listening (Oscar, 2026-09-17).
        guard pet.running else { return "asleep" }
        switch phase {
        case .idle:      return "idle"
        case .listening: return "listening"
        case .thinking:  return "thinking"
        case .speaking:  return "speaking"
        }
    }

    private var face: some View {
        // Her face is one of the drawn ten. `FaceView` and the model pages it
        // loads are untouched on disk; they are simply not offered any more
        // (Oscar, 2026-09-29), and an old saved portrait reads as the default.
        let saved = FaceStyle(rawValue: faceStyle) ?? .ribbon
        return VoiceVisual(style: saved == .portrait ? .ribbon : saved,
                           state: voiceState, amplitude: Double(pet.level),
                           tint: phaseColor,
                           scale: faceScale, bloom: faceBloom, speed: faceSpeed)
            .offset(x: faceX, y: faceY)
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

    /// Who else is in the room, and who is talking.
    ///
    /// Small and always-on rather than a screen he has to open: the two things
    /// that go wrong in a group are invisible otherwise -- a device that
    /// dropped out, and a microphone he thinks is here when it is on the
    /// kitchen counter. The ear is marked, the speaker is lit, and this device
    /// is the one in his own colour.
    private var company: some View {
        HStack(spacing: 14) {
            ForEach(room.members) { m in
                HStack(spacing: 4) {
                    if room.listener == m.device {
                        Image(systemName: "ear.fill").font(.system(size: 11))
                    }
                    Text(m.name)
                }
                .font(.system(size: 13, weight: room.holder == m.device
                                            ? .semibold : .regular))
                .foregroundStyle(room.holder == m.device ? voice
                                 : m.device == room.device ? listener
                                 : Color.white.opacity(0.45))
            }
        }
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.25), value: room.holder)
    }

    /// The conversation as bubbles: his on the right, hers on the left,
    /// the last four lines, older ones fading (Oscar, 2026-09-16).
    private var transcript: some View {
        VStack(alignment: .leading, spacing: voiceBubbles ? 8 : 4) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                Group {
                    if voiceBubbles {
                        ChatBubble(text: m.text, mine: m.mine, voice: voice, mineColor: mineColor)
                    } else {
                        TerminalLine(text: m.text, mine: m.mine, voice: voice,
                                     mineColor: mineColor)
                    }
                }
                .opacity(0.4 + 0.6 * Double(i + 1) / Double(messages.count))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .animation(.easeOut(duration: 0.3), value: messages)
        .padding(.horizontal, 0)
        .padding(.bottom, 24)
    }

    /// The screen's buttons, spoken (Oscar, 2026-09-17). She still answers
    /// the line; this only presses the button. No "unmute": a muted mic hears
    /// nothing, so that one stays a tap.
    private func obey(_ text: String) {
        switch VoiceCommand(text) {
        case .transcript(let on)?: showTranscript = on
        case .settings(let open)?: showSettings = open
        case nil: break
        }
    }

    private let brain = Brain()

    /// Into the desk's voice log, which the conversation history reads.
    private func record(_ text: String, _ kind: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { brain.logVoice(t, kind: kind) }
    }

    private func say(_ text: String, mine: Bool) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(Bubble(mine: mine, text: t))
        if messages.count > 4 { messages.removeFirst(messages.count - 4) }
    }

    /// The same twenty bars all the way through, because a second widget
    /// appearing elsewhere on the screen was the thing that made her look
    /// busy in a different place from where she listens. No word under it:
    /// the legend top left already names the colour (Oscar, 2026-09-16).
    private var meter: some View {
        Group {
            switch phase {
            // One travelling wave for every state. Thinking and speaking
            // run it at full height; listening scales it by his
            // microphone, so it is a mic light; idle holds it flat.
            case .thinking, .speaking: wave(phaseColor, gain: 1)
            case .listening: wave(phaseColor, gain: Double(live.micLevel))
            case .idle:      wave(phaseColor, gain: 0)
            }
        }
        .frame(height: 36)
    }

    /// A wave running left to right. `TimelineView` drives it off the frame
    /// clock rather than an animation on a `@State` flag: twenty bars each
    /// with their own phase is exactly the shape SwiftUI's implicit
    /// animation cannot express.
    private func wave(_ tint: Color, gain: Double) -> some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // She speaks faster than she thinks, and the bars should say so
            // before the colour does.
            let speed = phase == .speaking ? 1.5 : 0.85
            HStack(spacing: 5) {
                ForEach(0..<20, id: \.self) { i in
                    let offset = Double(i) / 20 - t * speed
                    let w = (sin(offset * .pi * 2) + 1) / 2 * gain
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(0.18 + w * 0.82))
                        .frame(width: 9, height: 6 + w * 30)
                }
            }
            .shadow(color: tint.opacity(0.7 * max(gain, 0.3)), radius: 10)
            .animation(.easeOut(duration: 0.12), value: gain)
        }
    }
}

// MARK: - her screen

/// A page she put on screen, in the app's own sheet.
///
/// The three modes are the desk's decision (server/reader.py), mirroring
/// arisu-voice.js `drawPage` so the app and the web face show the same thing
/// for the same page: `frame` is the site itself in a web view, `reader` is
/// the text or the headlines the desk could read off it, and `tab` is the
/// honest note -- his logins cannot survive our web view, so it goes to Safari.
struct PageSheet: View {
    let page: ShowPage
    let close: () -> Void
    @Environment(\.openURL) private var openURL

    private var heads: [String] { page.headlines ?? [] }
    private var body_text: String { page.text ?? "" }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(page.host ?? page.url)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: close)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Safari") { if let u = URL(string: page.url) { openURL(u) } }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if page.mode == "frame" {
            WebPage(url: URL(string: page.url))
        } else if page.mode == "tab" || (heads.isEmpty && body_text.isEmpty) {
            note(page.mode == "tab"
                 ? "This one needs you signed in, so it opens in your own browser."
                 : (page.error ?? "I could not read anything off that page."))
        } else if !heads.isEmpty {
            List(Array(heads.enumerated()), id: \.offset) { _, head in
                Text(head)
            }
        } else {
            ScrollView { Text(body_text).padding() }
        }
    }

    private func note(_ line: String) -> some View {
        VStack(spacing: 16) {
            Text(line).multilineTextAlignment(.center)
            Button("Open in Safari") { if let u = URL(string: page.url) { openURL(u) } }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One line of the conversation: his on the right in magenta, hers on the
/// left in cyan, the same glass bubble for both. Shared by the subtitles and
/// the typed chat so the two read as one feature.
struct ChatBubble: View {
    let text: String
    let mine: Bool
    let voice: Color
    let mineColor: Color
    /// A darker glass for the typed chat, which sits over her face for longer.
    var solid = false

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 80) }
            Text(text)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(mine ? mineColor : voice)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(solid ? Color.black.opacity(0.62) : Color.white.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke((mine ? mineColor : voice).opacity(0.35)))
                .textSelection(.enabled)
            if !mine { Spacer(minLength: 80) }
        }
    }
}

/// One line of the conversation as the chat page's terminal draws it: his
/// prefixed with a prompt in cyan, hers under a bold `arisu:` in white. The
/// alternative to `ChatBubble`, chosen in Settings and carried into the chat
/// page as `?style=` so both screens agree (Oscar, 2026-09-26).
struct TerminalLine: View {
    let text: String
    let mine: Bool
    let voice: Color

    /// His colour, so that who is who never depends on the style. It used to
    /// draw him in her cyan and her in white (Oscar, 2026-09-29).
    var mineColor: Color = Skin.mag

    var body: some View {
        Text(mine ? "> " + text : text)
            .font(.system(size: 17, weight: mine ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(mine ? mineColor : voice)
            .shadow(color: .black.opacity(0.85), radius: 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
/// The site itself. No script of hers lives in here, and no data of his goes
/// in: a fresh non-persistent store, so the web view carries no cookies from
/// anywhere else and leaves none behind.
struct WebPage: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: config)
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard let url, view.url != url else { return }
        view.load(URLRequest(url: url))
    }
}

/// A spoken button press, from his transcribed line. Explicit phrases only, so
/// talking *about* the transcript does not flip it.
enum VoiceCommand: Equatable {
    case transcript(Bool), settings(Bool)

    init?(_ line: String) {
        let t = line.lowercased()
        func has(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        let on = #"\b(show|open|turn on|switch on)\b"#, off = #"\b(hide|close|turn off|switch off)\b"#
        let chat = #"\b(transcript|subtitles|captions|chat)\b"#
        if has(on + ".{0,12}" + chat) { self = .transcript(true) }
        else if has(off + ".{0,12}" + chat) { self = .transcript(false) }
        else if has(on + ".{0,12}\\bsettings\\b") { self = .settings(true) }
        else if has(off + ".{0,12}\\bsettings\\b") { self = .settings(false) }
        else { return nil }
    }
}
