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
    /// The moving bars at the bottom, on or off (Settings > Face).
    @AppStorage("arisu.meter") private var showMeter = true
    @State private var showSettings = false
    /// The typed chat: its own screen, the terminal page lain serves
    /// (arisu/chat.html) full screen over her. Voice and chat are two
    /// separate UIs in one app (Oscar, 2026-09-23).
    @State private var showChat = false
    /// The recent lines of both of them, oldest first, as chat bubbles.
    @State private var messages: [Bubble] = []
    /// Legend and buttons start hidden; a tap on the screen shows them, the
    /// next hides them (Oscar, 2026-09-17).
    @State private var chromeShown = false

    private struct Bubble: Identifiable, Equatable {
        let id = UUID()
        let mine: Bool
        let text: String
    }

    /// What she says, always. The mood still tints the room around her, but
    /// the words themselves stay one colour -- "hot" rendered them at
    /// (1.0, 0.30, 0.42), which reads as magenta and collided with the
    /// magenta the meter once used to mean she is working.
    private let voice = Color(red: 0.27, green: 0.90, blue: 0.97)
    /// His chat bubbles: the legend's thinking magenta.
    private let mineColor = Color(red: 1.0, green: 0.22, blue: 0.78)

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
    /// What each colour means, one row top left, with the current one lit.
    private var legend: some View {
        HStack(spacing: 18) {
            ForEach([(Phase.idle, "idle"), (.listening, "listening"),
                     (.thinking, "thinking"), (.speaking, "speaking")], id: \.1) { p, name in
                let (r, g, b) = Self.rgb(p)
                let c = Color(red: r, green: g, blue: b)
                HStack(spacing: 8) {
                    Circle().fill(c).frame(width: 10, height: 10)
                        .shadow(color: c.opacity(0.8), radius: phase == p ? 6 : 0)
                    Text(name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(c)
                }
                .opacity(phase == p ? 1 : 0.45)
            }
        }
        .shadow(color: .black.opacity(0.85), radius: 4)
        .padding(.leading, 26)
        .padding(.top, 30)
        .animation(.easeInOut(duration: 0.25), value: phase)
        .allowsHitTesting(false)
    }

    private var groundLight: Double {
        switch phase {
        case .idle:      return 0.06
        case .listening: return 0.12
        case .thinking:  return 0.1
        case .speaking:  return 0.15
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
                        .padding(.trailing, 260)
                    }
                    // A meter for a microphone that is down would be a lie.
                    if pet.running && showMeter { meter.padding(.bottom, 22) }
                    else { Color.clear.frame(height: 36).padding(.bottom, 22) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            // Double tap: the conversation on or off. Single tap: the chrome.
            .onTapGesture(count: 2) { pet.toggleRunning() }
            .onTapGesture { chromeShown.toggle() }
            .overlay(alignment: .bottomTrailing) { if chromeShown { controls.transition(.opacity) } }
            .overlay(alignment: .topLeading) { if chromeShown { legend.transition(.opacity) } }
            .overlay(alignment: .topTrailing) { modeToggle }
            .animation(.easeOut(duration: 0.2), value: chromeShown)
        }
        .ignoresSafeArea()
        // A page she was asked to show. The desk already decided how it can be
        // shown, so this only draws it.
        .sheet(item: $live.page) { PageSheet(page: $0) { live.page = nil } }
        .sheet(isPresented: $showSettings) { SettingsSheet(pet: pet, live: live) }
        .fullScreenCover(isPresented: $showChat) { ChatScreen { showChat = false } }
        .onChange(of: pet.heard) { _, t in say(t, mine: true); obey(t) }
        .onChange(of: pet.line) { _, t in say(t, mine: false) }
        .animation(.easeInOut(duration: 0.25), value: pet.thinking)
        .animation(.easeInOut(duration: 0.25), value: live.thinking)
        .animation(.easeInOut(duration: 0.25), value: pet.running)
        .onAppear {
            Task { await pet.arrive() }
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
            // Hold-to-talk and mute removed (Oscar, 2026-09-23). Neither is
            // saved across launches, so nothing is left switched on.
            // Group button removed (Oscar, 2026-09-23); the room stays solo.
            // Which device is listening. Shown as soon as there is anyone
            // else to hand it to, rather than only in a group: hiding it until
            // the mode is switched means the one control he needs to fix a
            // room appears only after the room is already wrong.
            if room.members.count > 1 {
                iconButton(room.isListener ? "ear.fill" : "ear",
                           tint: room.isListener ? listener : off) {
                    room.listenHere()
                }
            }
            iconButton("slider.horizontal.3", tint: off) {
                showSettings = true
            }
        }
        .padding(.trailing, 26)
        .padding(.bottom, 26)
    }

    /// Voice | Chat: the one switch between her two screens, the same place and
    /// look as the web's and as the chat page's own (Oscar, 2026-09-23).
    private var modeToggle: some View {
        let cyan = Color(red: 0.27, green: 0.90, blue: 0.97)
        return HStack(spacing: 0) {
            Image(systemName: "waveform")
                .foregroundStyle(Color(red: 0.02, green: 0.09, blue: 0.10))
                .frame(width: 54, height: 38)
                .background(cyan)
                .accessibilityLabel("Voice")
            Button { showChat = true } label: {
                Image(systemName: "terminal").foregroundStyle(cyan)
                    .frame(width: 54, height: 38)
            }
            .accessibilityLabel("Chat")
        }
        .font(.system(size: 19, weight: .semibold))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cyan.opacity(0.55)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 24)
        .padding(.trailing, 26)
    }

    private func iconButton(_ symbol: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 52, height: 46)
                .padding(10)
                // The only thing keeping a pale glyph legible over the pale
                // part of her face, now that there is no capsule behind it.
                .shadow(color: .black.opacity(0.85), radius: 5)
                .contentShape(Rectangle())
        }
    }

    /// The renderer's own vocabulary. `Phase` already says all of it except
    /// asleep, which is not a phase of a conversation but the absence of one:
    /// the microphone is down and there is nothing to be idle about.
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
        // No shadow, no mask, no drift. The colour-split, the bloom and the
        // soft bottom edge are all things the renderer does itself now, and
        // stacking SwiftUI's versions on top only muddied them.
        FaceView(face: pet.face, state: faceState, amplitude: Double(pet.level),
                 live2d: live2dFace, model: pet.model,
                 glow: [phaseRGB.0, phaseRGB.1, phaseRGB.2]
                     .map { String(Int($0 * 255)) }.joined(separator: ","),
                 tune: pet.glow)
            .allowsHitTesting(false)
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

    /// The conversation as chat bubbles: his on the right, hers on the left,
    /// the last four lines, older ones fading (Oscar, 2026-09-16).
    private var transcript: some View {
        VStack(spacing: 8) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                ChatBubble(text: m.text, mine: m.mine, voice: voice, mineColor: mineColor)
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

/// The typed chat, full screen and edge to edge: lain's terminal page with no
/// iOS bar over it, so it reads as the app's other screen. Its own "face"
/// button posts `close` to the `arisu` handler, which returns to her.
struct ChatScreen: UIViewRepresentable {
    let close: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(close: close) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "arisu")
        let web = WKWebView(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) { web.isInspectable = true }
        // Her own black while the page loads, not a white flash.
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if let url = URL(string: "chat.html?app=1", relativeTo: Brain.base) {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "arisu")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            if (m.body as? String) == "close" { close() }
        }
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
