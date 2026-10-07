import SwiftUI
import WebKit
import UIKit

/// The hologram: `FaceView` for her, plus scanlines and a sweep over the top.
///
/// Her face used to be three stacked copies of one still -- a solid and two
/// colour-split ghosts on a slow drift -- which read well from the sofa and
/// did nothing at all in response to her. It is a live renderer now, and the
/// colour-split, the bloom and the soft bottom edge moved inside it. The
/// scanlines and the sweep stayed here because they belong to the room rather
/// than to her, and they still cost nothing per frame.
struct ContentView: View {
    enum Presentation: String, CaseIterable, Identifiable {
        case base, free, singularity
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    @ObservedObject var pet: Pet
    @ObservedObject var live: Live
    @ObservedObject var room: Room
    @State private var sweep = false
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
    @AppStorage(Skin.freeFormKey) private var freeForm = false
    @AppStorage(Look.key) private var look = Look.classic
    @State private var wake = WakeListener()
    @Environment(\.scenePhase) private var scene
    @State private var showSettings = false
    @State private var showNew = false
    /// The sheet that puts his pages on a screen (27.0).
    @State private var showScreens = false
    /// The guided tour running now, and which stop it is on.
    @State private var tour: [TourStep]?
    @State private var tourIndex = 0
    /// The mode before a tour, to put him back after.
    @State private var modeBeforeTour: Presentation = .base
    /// The last version whose tour started by itself: a new version opens on
    /// its tour once, then never again unless he asks (Oscar, 2026-10-02).
    @AppStorage("arisu.touredVersion") private var touredVersion = ""
    /// The demo playing now, which stop it is on, and the task stepping it
    /// (21.0). Its simulated inputs are read from `demoAct`.
    @State private var demo: [DemoStep]?
    @State private var demoIndex = 0
    @State private var demoRun: Task<Void, Never>?
    /// Summoned on Singularity with no call behind her: her arrival and her
    /// rings awake, the iPad listening for 醒来, which is what starts the call
    /// (Oscar, 2026-10-02: summoning shows the conversation look without
    /// opening a call).
    @State private var present = false
    /// Night hours (22.0): not listening for 醒来 until morning.
    @State private var night = false
    /// This iPad as a screen on lain's /screens channel, by the name `ipad`
    /// (23.0): the last push it opened, kept across launches so a page is
    /// opened once rather than on every launch, and the page it put up, so
    /// clearing the screen closes that page and no other.
    @AppStorage("arisu.screenRev") private var screenRev = -1
    @State private var screenShown: String?
    /// What the screen holds now, open or not, and what it held before: the
    /// way back to a page he closed (24.0, Backlog: "Each screen remembers
    /// what it was showing and comes back to it").
    @State private var screenHeld: ScreenState?
    @State private var screenTrail: [ScreenVisit] = []
    static var screenName: String {
        #if DEBUG
        // To check the whole path in the simulator without writing to the
        // desk: follow a screen that already shows something, read-only.
        // `simctl launch … -arisu.screenName desk`.
        if let n = UserDefaults.standard.string(forKey: "arisu.screenName") { return n }
        #endif
        return "ipad"
    }
    @AppStorage(Night.fromKey) private var nightFrom = Night.from
    @AppStorage(Night.toKey) private var nightTo = Night.to
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
    /// The typed chat: its own screen, the terminal page lain serves
    /// (arisu/chat.html) full screen over her. Voice and chat are two
    /// separate UIs in one app (Oscar, 2026-09-23).
    @State private var showChat = true
    /// Voice mode shows only her until he taps: then the transcript, the
    /// command suggestions and the bar; another tap hides them (Oscar,
    /// 2026-10-01). Replaces the subtitles button and its saved setting.
    @State private var chrome = false
    @State private var shownSourceLinks = Set<URL>()
    /// The typed thread. Held here rather than inside the pane so that it
    /// survives switching to her voice and back -- the conversation is one
    /// thing, and re-fetching it every time he speaks would make it blink.
    @StateObject private var chat = Chat()
    /// Held, not watched: its level changes thirty times a second, and only
    /// her face draws it (through `Metered`), not this whole view (18.0).
    @State private var music = MacMusic()
    /// lain's day, for the panel beside her (12.0).
    @StateObject private var info = LainInfo()
    /// What the conversation is about, lit on the panel for a minute and a
    /// half after it was last said, with the panel up even if the chrome is not.
    @State private var focus: GlanceFocus?
    @State private var focusAt = Date.distantPast
    /// Open the chat on its history the moment it is shown -- the room's
    /// History button leaves the room and lands there.
    @State private var chatHistory = false
    /// The recent lines of both of them, oldest first, as chat bubbles.
    @State private var messages: [Bubble] = []
    /// The Pencil touched the screen: the scribble canvas is up.
    @State private var scribbling = false

    private var presentation: Presentation {
        if look == .singularity { return .singularity }
        return freeForm ? .free : .base
    }

    private func setPresentation(_ next: Presentation) {
        if next != .singularity {
            look = .classic
            freeForm = next == .free
        } else {
            freeForm = false
            look = .singularity
        }
    }

    private func cyclePresentation(_ by: Int) {
        let all = Presentation.allCases
        let index = all.firstIndex(of: presentation) ?? 0
        setPresentation(all[(index + by + all.count) % all.count])
    }

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
        ZStack {
        if look == .classic {
        // Free form (Oscar, 2026-10-02): she is always there, large and dim in
        // the middle of the whole screen, behind the controls, breathing
        // slowly. Voice brings this same animation forward over the layout.
        if freeForm {
            freeFormVisual
                .opacity(showChat ? 0.55 : 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(showChat ? 0 : 1)
        }
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
                            HStack(spacing: 0) {
                                RecordPanel { pet.stop() }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .tourSpot("record")
                                Rectangle().fill(Skin.cyan.opacity(0.3)).frame(width: 1)
                                voiceCommandsPanel
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(maxHeight: .infinity)
                            DeckRail().frame(maxHeight: .infinity).tourSpot("deck")
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
        .opacity(freeForm && !showChat ? 0.08 : 1)
        .allowsHitTesting(!freeForm || showChat)
        .accessibilityHidden(freeForm && !showChat)
        if freeForm && !showChat {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { pet.toggleRunning() }
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { chrome.toggle() } }
                .overlay(alignment: .topTrailing) {
                    if chrome {
                        commandButtons
                            .padding(.top, 24)
                            .padding(.trailing, 24)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if chrome {
                        transcript
                            .padding(.leading, 34)
                            .padding(.trailing, 24)
                            .padding(.bottom, 76)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Keep the way back and microphone reachable over the faded screen.
                    HStack(spacing: 10) {
                        squareButton("text.bubble", "Commands and transcript",
                                     tint: chrome ? Skin.cyan : off) {
                            withAnimation(.easeOut(duration: 0.2)) { chrome.toggle() }
                        }
                        squareButton(live.muted || !pet.running ? "mic.slash" : "mic.fill",
                                     "Microphone", tint: pet.running && !live.muted ? listener : off) {
                            pet.toggleMicrophone()
                        }
                        squareButton("keyboard", "Back to the chat", tint: Self.mag) { toChat() }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 28)
                }
                .zIndex(2)
        }
        } else {
            // A version that is all her (Oscar, 2026-10-01).
            Metered(meter: pet.meter, music: music) { level, _ in
                RealmView(level: level, idle: voiceState == .idle,
                          speaking: voiceState == .speaking,
                          running: pet.running || present || demoAct.present,
                          tint: phaseColor, status: (pet.running ? stateWord : idleWord).uppercased(),
                          micOn: pet.running && !live.muted,
                          onHer: { pet.toggleMicrophone() },
                          onSummon: {
                              // Held anywhere: she arrives, and no call opens --
                              // 醒来 starts that (Oscar, 2026-10-02). Held again:
                              // she goes, ending the call if there is one.
                              if pet.running { pet.toggleRunning() }
                              else {
                                  if !present { Awaken.play() }
                                  present.toggle()
                              }
                          },
                          // The room is alive the moment he walks in; two taps
                          // are what start her listening (Oscar, 2026-10-03).
                          onTalk: { if pet.running { pet.toggleRunning() } else { summon() } },
                          chant: chantLine, fakeMusic: demoAct == .music,
                          info: info, night: night || demoAct == .night)
            }
            .transition(.opacity)
        }
        }
        .animation(.easeInOut(duration: 0.4), value: look)
        .animation(.easeInOut(duration: 0.4), value: freeForm)
        .animation(.easeInOut(duration: 0.5), value: showChat)
        .background(ThreeFingerSwipe { cyclePresentation($0) })
        .background(Color.black)
        .background(PencilWatch(enabled: !scribbling) { scribbling = true })
        .overlay { if scribbling { ScribbleCanvas { scribbling = false } } }
        .overlayPreferenceValue(TourSpots.self) { spots in
            if let tour {
                TourOverlay(steps: tour, spots: spots, index: $tourIndex) { endTour() }
                    .transition(.opacity)
            }
        }
        .onChange(of: tourIndex) { _, i in if let tour, i < tour.count { stage(tour[i].scene) } }
        .overlay {
            if let demo {
                DemoCard(steps: demo, index: demoIndex) { endDemo() }.transition(.opacity)
            }
        }
        .fontDesign(.monospaced)
        .ignoresSafeArea()
        // A page she was asked to show. The desk already decided how it can be
        // shown, so this only draws it.
        .sheet(item: $live.page) {
            PageSheet(page: $0, close: { live.page = nil }, front: demoAct == .pagesNext ? 1 : 0,
                      toDesk: Self.screenName == "desk" ? nil : { pages in
                          demo == nil ? await chat.put("desk", pages: pages) != nil : false
                      },
                      stagedSent: demoAct == .toDesk)
        }
        // Put a page on a screen, by his hand (27.0). Up while he has it open,
        // or while a demo stop shows it.
        .sheet(isPresented: Binding(get: { showScreens || demoAct.screens },
                                    set: { if !$0 { showScreens = false } })) {
            ScreenSheet(chat: chat, changed: { name in
                if name == Self.screenName { Task { await followScreen() } }
            }, close: { showScreens = false }, open: { held in
                showScreens = false
                // One sheet at a time: the page window waits for this one to go.
                Task { try? await Task.sleep(for: .seconds(0.7)); reopen(held) }
            }, staged: demoAct.screens ? demoAct : .none)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(pet: pet, live: live) }
        .sheet(isPresented: $showNew) { ReleasesSheet { startTour() } onDemo: { startDemo($0) } }
        .onChange(of: pet.heard) { _, t in
            lastSpoke = Date(); say(t, mine: true); obey(t); notice(t); record(t, "heard")
        }
        .onChange(of: pet.line) { _, t in
            lastSpoke = Date(); say(t, mine: false); notice(t); record(t, "answer")
        }
        .onChange(of: live.sourceAnswer) { _, answer in
            // Display-only source links: never record these as spoken answers.
            for url in pageLinks(answer) where shownSourceLinks.count < 64 && !shownSourceLinks.contains(url) {
                shownSourceLinks.insert(url)
                say(url.absoluteString, mine: false)
            }
        }
        .onChange(of: pet.running) { _, on in
            if on { shownSourceLinks.removeAll() }
            record(on ? "call started" : "call ended", "call")
            // She leaves with the call she was summoned for.
            if !on { present = false }
            // A call she starts herself -- a queued brief on arrival -- is
            // voice, so the screen goes to her rather than staying on the
            // typed thread while she talks (Oscar, 2026-09-30).
            if on && showChat { showChat = false; lastSpoke = Date() }
        }
        .animation(.easeInOut(duration: 0.25), value: pet.thinking)
        .animation(.easeInOut(duration: 0.25), value: live.thinking)
        .animation(.easeInOut(duration: 0.25), value: pet.running)
        .task { await closeQuietRoom() }
        // lain's day, for the panel in both modes; one reader for the app.
        .task { await info.watch() }
        // A typed exchange about his running or habits brings the panel up in
        // the chat, as a spoken one does beside her. Only lines just added:
        // a whole thread loading is not anyone talking.
        .onChange(of: chat.lines.count) { old, new in
            guard new > old, new - old <= 2 else { return }
            for l in chat.lines.suffix(new - old) { notice(l.text) }
        }
        // 醒来, heard on the device while she is asleep and the app is in front.
        .task(id: pet.running || scene != .active || night) {
            guard !pet.running && scene == .active && !night else { wake.stop(); return }
            wake.onWake = { summon() }
            await wake.start()
        }
        // Pages pushed to this screen (23.0): a 100-byte read every four
        // seconds while the app is in front; nothing while it is away.
        .task(id: scene == .active) {
            guard scene == .active else { return }
            while !Task.isCancelled {
                await followScreen()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        // Night begins and ends on the hour; a look twice a minute is enough,
        // and only a change is published (17.0).
        .task(id: [nightFrom, nightTo]) {
            while !Task.isCancelled {
                let n = Night.on(from: nightFrom, to: nightTo)
                if n != night { night = n }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // Leaving Singularity sends her away; so does ten minutes of nobody
        // saying 醒来, because a summoned room draws at full rate (21.0).
        .onChange(of: look) { _, l in if l != .singularity { present = false } }
        .task(id: present) {
            guard present else { return }
            try? await Task.sleep(for: .seconds(600))
            if !Task.isCancelled && !pet.running { present = false }
        }
        .onAppear {
            Task { await pet.arrive() }
            #if DEBUG
            // For checking a demo in the simulator, where nothing can tap:
            // `simctl launch … -arisu.demo 21.0 [-arisu.demoStop 2]`; and the
            // sheet behind the sparkles, on a tab: `-arisu.sheetTab 1`; Settings:
            // `-arisu.settings YES`; Put on a screen: `-arisu.screens YES`.
            if UserDefaults.standard.object(forKey: "arisu.sheetTab") != nil { showNew = true }
            if UserDefaults.standard.bool(forKey: "arisu.settings") { showSettings = true }
            if UserDefaults.standard.bool(forKey: "arisu.screens") { showScreens = true }
            if let v = UserDefaults.standard.string(forKey: "arisu.demo"),
               let r = Releases.all.first(where: { $0.version == v }) {
                Task { try? await Task.sleep(for: .seconds(2)); startDemo(r.demo) }
                return
            }
            #endif
            if touredVersion != Releases.running && !Releases.current.tour.isEmpty {
                touredVersion = Releases.running
                Task { try? await Task.sleep(for: .seconds(1.5)); startTour() }
            }
            withAnimation(.linear(duration: 5.6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }

    /// Open what was pushed to this screen since the last look, or close it
    /// when the screen was cleared. A failed read changes nothing.
    private func followScreen() async {
        let got: ScreenState?
        do { got = try await chat.screen(Self.screenName) } catch { return }
        if got != screenHeld { screenHeld = got }
        guard let s = got else {
            if screenRev != -1 {
                screenRev = -1
                if let shown = screenShown, live.page?.url == shown { live.page = nil }
                screenShown = nil
            }
            return
        }
        guard s.rev != screenRev else { return }
        screenRev = s.rev
        guard demo == nil, let page = await chat.screenPage(s) else { return }
        screenShown = page.url
        live.page = page
    }

    /// Put a page this screen holds, or held, back up. Only this iPad's sheet:
    /// the desk's record of the screen is not touched.
    private func reopen(_ s: ScreenState) {
        Task { if let page = await chat.screenPage(s) { live.page = page } }
    }

    /// The screen's page as the chip shows it: the real one, or the demo's
    /// page while a demo or the tour stop about the chip needs one to point at.
    private var heldPage: ScreenState? {
        let staged = ScreenState(url: DemoAct.screenPage.url, title: "Screen ipad", rev: 0)
        if demoAct == .held { return staged }
        if demo != nil { return nil }
        if let tour, tourIndex < tour.count, tour[tourIndex].spot == "screenBack" { return screenHeld ?? staged }
        return screenHeld
    }

    /// Back to the screen: lit while it holds a page, a press opens it again,
    /// a long press lists what it showed before.
    @ViewBuilder private var screenChip: some View {
        if let held = heldPage {
            squareButton("rectangle.on.rectangle", "Back to the screen: " + held.title,
                         tint: Skin.mag, stroke: 0.7, ink: .white) {
                if demo == nil && held.url != DemoAct.screenPage.url { reopen(held) }
            }
            .contextMenu {
                Section("On screen " + Self.screenName) {
                    Button(held.title.isEmpty ? held.url : held.title, systemImage: "rectangle.on.rectangle") {
                        reopen(held)
                    }
                }
                if !screenTrail.isEmpty {
                    Section("Shown before") {
                        ForEach(screenTrail.filter { $0.url != held.url }, id: \.self) { v in
                            Button(v.title.isEmpty ? v.url : v.title) {
                                reopen(ScreenState(url: v.url, title: v.title, rev: 0))
                            }
                        }
                    }
                }
            }
            .tourSpot("screenBack")
            // The trail changes only when something new is pushed: read it
            // then, not every four seconds.
            .task(id: held.rev) { screenTrail = await chat.screenTrail(Self.screenName) }
        }
    }

    /// What the screen says while no call is on: that she can be woken, or
    /// why she cannot be by voice.
    private var idleWord: String {
        if let l = demoAct.line { return l }
        if night && demo == nil { return "asleep until " + Night.until }
        if let p = wake.problem { return "wake word off: " + p }
        return wake.listening ? "say 醒来 to wake her" : "not listening"
    }

    // MARK: Demos

    /// What the demo stop showing now pretends, if a demo is playing.
    private var demoAct: DemoAct {
        guard let demo, demoIndex < demo.count else { return .none }
        return demo[demoIndex].act
    }

    /// Play a demo: each stop stages its screen, pretends its input for its
    /// seconds, and the last one puts him back where he was. Nothing here
    /// opens the microphone or reaches the Mac or the desk.
    private func startDemo(_ steps: [DemoStep]) {
        guard !steps.isEmpty, tour == nil else { return }
        demoRun?.cancel()
        var from = 0
        #if DEBUG
        from = min(max(0, UserDefaults.standard.integer(forKey: "arisu.demoStop")), steps.count - 1)
        #endif
        modeBeforeTour = presentation
        demoIndex = from
        withAnimation { demo = steps }
        demoRun = Task {
            for i in from..<steps.count {
                demoIndex = i
                stage(steps[i].scene)
                // The line she would speak as the call starts, carved as it is
                // then; spoken by nobody.
                if steps[i].act == .wake { chantLine = Self.victory.randomElement()! }
                if let staged = steps[i].act.page { live.page = staged }
                else if DemoAct.staged(live.page) { live.page = nil }
                try? await Task.sleep(for: .seconds(steps[i].seconds))
                if Task.isCancelled { return }
            }
            endDemo()
        }
    }

    private func endDemo() {
        demoRun?.cancel()
        demoRun = nil
        if DemoAct.staged(live.page) { live.page = nil }
        withAnimation { demo = nil; chrome = false }
        demoIndex = 0
        stage(.chat)
        setPresentation(modeBeforeTour)
    }

    // MARK: Tours

    /// The scene of the tour stop showing now, if a tour is running.
    private var tourScene: TourScene? {
        guard let tour, tourIndex < tour.count else { return nil }
        return tour[tourIndex].scene
    }

    private func startTour() {
        let steps = Releases.current.tour
        guard !steps.isEmpty else { return }
        tourIndex = 0
        #if DEBUG
        // For checking a tour in the simulator, where nothing can tap:
        // `simctl launch … -arisu.tourStop 3` opens the tour on its fourth stop.
        tourIndex = min(max(0, UserDefaults.standard.integer(forKey: "arisu.tourStop")), steps.count - 1)
        #endif
        modeBeforeTour = presentation
        stage(steps[tourIndex].scene)
        withAnimation { tour = steps }
    }

    private func endTour() {
        withAnimation { tour = nil; chrome = false }
        stage(.chat)
        setPresentation(modeBeforeTour)
    }

    /// Put the screen where a tour stop needs it, without opening the
    /// microphone: voice mode is shown, not started.
    private func stage(_ scene: TourScene) {
        switch scene {
        case .keep: break
        case .chat: setPresentation(.base); deckShown = true; showChat = true
        case .chatGlance: setPresentation(.base); deckShown = true; showChat = true
        case .voice: setPresentation(.base); showChat = false
        case .glance: setPresentation(.base); showChat = false; withAnimation { chrome = true }
        case .singularity: setPresentation(.singularity)
        }
    }

    /// The lit divider, and the handle that moves it. Clamped so neither side
    /// can be dragged away to nothing.
    private func seam(total: CGFloat) -> some View {
        // No line: only the drag handle stays (Oscar, 2026-10-01).
        Color.clear.frame(width: 2)
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
        if showChat || freeForm {
            ChatPane(chat: chat, openHistory: $chatHistory, toVoice: { toVoice() },
                     show: { live.page = $0 }, glance: info.glance, focus: $focus, shown: tourScene == .chatGlance,
                     character: room.character, calling: pet.running, active: showChat)
                .equatable()
        } else {
            hologram.tourSpot("her")
        }
    }

    private var hologram: some View {
        GeometryReader { geo in
            // The face is a square tile, so in landscape it can only ever cover
            // the middle. The ground it sits on has to reach the edges by
            // itself -- a fixed radius left unlit corners on the wide screen.
            let reach = max(geo.size.width, geo.size.height)
            ZStack {
                Grid(tint: Skin.cyan)
                // The ground under her carries the same colour as the meter,
                // so the state is readable from across the room, where the
                // twenty bars are not.
                RadialGradient(colors: [phaseColor.opacity(groundLight),
                                        phaseColor.opacity(groundLight / 4), .clear],
                               center: .center, startRadius: 4, endRadius: reach * 0.75)
                    .animation(.easeInOut(duration: 0.35), value: phaseColor)

                face
                scanlines.allowsHitTesting(false)

                // The day beside her, top left: up with the chrome, or by
                // itself while they talk about his running or habits.
                VStack {
                    HStack {
                        if glanceShown {
                            // Narrower on a narrow pane, so the bubbles on the right stay clear.
                            GlancePanel(glance: info.glance, focus: demoAct == .running ? .running : focus,
                                        width: min(320, max(240, geo.size.width - 250)))
                                .tourSpot("glance")
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 24)
                .padding(.leading, 34)

                VStack {
                    Spacer()
                    if room.isGroup { company }
                    if chrome {
                        HStack {
                            transcript
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 34)
                        .padding(.trailing, 24)
                        .transition(.opacity)
                        roomBar.transition(.opacity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(Brackets(tint: Skin.mag).padding(10))
            .animation(.easeOut(duration: 0.3), value: glanceShown)
            .contentShape(Rectangle())
            // Double tap: the conversation on or off. Single tap: the chrome.
            .onTapGesture(count: 2) { pet.toggleRunning() }
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { chrome.toggle() } }
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
            // Her level takes the place of what he would be typing. A meter
            // for a microphone that is down would be a lie, so when there is
            // no call it is the state in words instead.
            // The bar keeps only what he presses; what she is doing is drawn
            // under her, where he is already looking (Oscar, 2026-09-29).
            // Her state in words where the bars were: the bars moved, the
            // words said which way (Oscar, 2026-09-30).
            Text("> " + (pet.running ? stateWord : idleWord).uppercased() + "_")
                .font(Skin.mono(16, .bold)).tracking(3)
                .foregroundStyle(pet.running ? phaseColor : Skin.ink)
                .shadow(color: pet.running ? phaseColor.opacity(0.8) : .clear, radius: 6)
                .animation(.easeInOut(duration: 0.25), value: phaseColor)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 36)
            squareButton(live.muted || !pet.running ? "mic.slash" : "mic.fill",
                         "Microphone",
                         tint: pet.running && !live.muted ? listener : off) {
                pet.toggleMicrophone()
            }
            squareButton("keyboard", "Back to the chat", tint: Self.mag) { toChat() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        // 28pt off the screen's edge, the same as the deck's keys (18 + its 10 inset).
        .padding(.bottom, 28)
    }

    private var glanceShown: Bool { chrome || focus != nil }

    /// A line about his running or habits brings the panel up with that part
    /// lit; it goes again ninety seconds after the last such line.
    private func notice(_ line: String) {
        guard let f = GlanceFocus(line) else { return }
        let mark = Date()
        focusAt = mark
        withAnimation { focus = f }
        Task {
            try? await Task.sleep(for: .seconds(90))
            if focusAt == mark { withAnimation { focus = nil } }
        }
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
        Masthead(presentation: Binding(get: { presentation }, set: { setPresentation($0) }))
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
        HStack(alignment: .top, spacing: 10) {
            masthead.tourSpot("title")
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
                             "Listen here", tint: room.isListener ? listener : Skin.cyan, stroke: 0.7, ink: .white) {
                    room.listenHere()
                }
            }
            screenChip
            // Put a page on a screen without her (27.0, Backlog: "A screen
            // command puts a view on a named screen without her").
            squareButton("display", "Put on a screen", tint: Skin.cyan, stroke: 0.7, ink: .white) {
                if demo == nil { showScreens = true }
            }
            .tourSpot("screenPut")
            squareButton("sparkles", "What's new", tint: Skin.mag, stroke: 0.7, ink: .white) {
                showNew = true
            }
            .tourSpot("whatsNew")
            squareButton("slider.horizontal.3", "Settings", tint: Skin.cyan, stroke: 0.7, ink: .white) {
                showSettings = true
            }
            .tourSpot("settings")
            // Shared by both screens.
            squareButton("square.grid.3x3.fill", "Deck",
                         tint: deckShown ? glow : Skin.cyan, stroke: 0.7, ink: .white) { deckShown.toggle() }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 22)
        .background(Grid(tint: Skin.mag))
    }

    /// Things he asks for often enough to press (Backlog: command buttons
    /// over her voice animation). A `line` is composed on the desk and said
    /// word for word; an `ask` is put to her as his own question.
    private static let commands: [(label: String, line: String?, ask: String?)] = [
        ("Today's brief", "brief", nil),
        ("Week review", "weekly", nil),
        ("AI signals", "signals", nil),
        ("What's next?", nil, "What is next on my plan today?"),
        ("How's my running?", nil, "How is my running going this week?"),
    ]

    private var voiceCommandsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ARISU//COMMANDS")
                .font(Skin.mono(12, .bold)).tracking(2)
                .foregroundStyle(Skin.mag)
                .lineLimit(1).minimumScaleFactor(0.8)
            commandButtons
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .console(Skin.cyan, brackets: Skin.mag)
        .padding(10)
        .tourSpot("commands")
    }

    private var commandButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.commands, id: \.label) { c in
                Button { press(c.line, c.ask) } label: {
                    Text(c.label)
                        .font(Skin.mono(14, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .plate { Capsule().fill(Color.black.opacity(0.45)) }
                        .edge { Capsule().stroke(Skin.cyan.opacity(0.5), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.label)
            }
        }
    }

    private func press(_ line: String?, _ ask: String?) {
        lastSpoke = Date()
        if let ask { notice(ask) }
        Task {
            if let line {
                guard let text = await brain.line(line) else { return }
                if pet.running { await live.speak(text) }
                else { pet.begin(saying: [QueuedCommand(id: line, text: text, show: nil)]) }
            } else if let ask {
                if !pet.running { pet.begin() }
                await live.ask(ask)
            }
        }
    }

    private func squareButton(_ symbol: String, _ label: String, tint: Color? = nil,
                              stroke: Double = 0.35, ink: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        IconButton(symbol: symbol, label: label, tint: tint ?? Skin.cyan,
                   stroke: stroke, ink: ink, action: action)
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
        // Mic off on the way in; he unmutes when he wants to talk (Oscar, 2026-10-01).
        live.muted = true
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

    /// Her sleeping face (23.0, Backlog: "She goes to her sleeping face and
    /// stops listening until morning"): at night, with no call, she is drawn
    /// dim and slow, a quarter of the frames, and no longer moves with the
    /// Mac's music. A call wakes her face with her.
    /// While a demo plays, only the demo says whether it is night.
    private var sleeping: Bool { (demo == nil ? night : demoAct == .night) && !pet.running }

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
        let state = voiceState
        return Metered(meter: pet.meter, music: music) { level, musicLevel in
            VoiceVisual(style: saved == .portrait ? .ribbon : saved,
                        state: state,
                        // Idle, she moves with his Spotify on the Mac.
                        amplitude: state == .idle ? max(level, musicLevel) : level,
                        // Mic off reads as cyan (Oscar, 2026-10-01).
                        tint: live.muted || !pet.running ? Skin.cyan : phaseColor,
                        scale: faceScale, bloom: faceBloom * (sleeping ? 0.5 : 1),
                        speed: faceSpeed * (sleeping ? 0.3 : 1), smoke: freeForm,
                        fps: sleeping ? 15 : nil)
        }
        .opacity(sleeping ? 0.5 : 1)
        .animation(.easeInOut(duration: 2), value: sleeping)
        // She steps aside for the panel rather than sitting under it.
        .offset(x: faceX + (glanceShown ? 150 : 0), y: faceY)
        .task(id: voiceState == .idle && !sleeping) {
            if voiceState == .idle && !sleeping { await music.listen() }
        }
    }

    /// One renderer stays mounted while the text fades, preserving its motion
    /// and its position across the whole screen when switching modes.
    private var freeFormVisual: some View {
        let saved = FaceStyle(rawValue: faceStyle) ?? .ribbon
        let state: VoiceState = showChat ? .idle : voiceState
        return Metered(meter: pet.meter, music: music) { level, musicLevel in
            VoiceVisual(style: saved == .portrait ? .ribbon : saved,
                        state: state,
                        amplitude: showChat ? 0 : (state == .idle ? max(level, musicLevel) : level),
                        tint: showChat || live.muted || !pet.running ? Skin.cyan : phaseColor,
                        scale: faceScale * 1.5, bloom: faceBloom * (sleeping ? 0.5 : 1),
                        speed: sleeping ? faceSpeed * 0.3 : showChat ? 0.45 : faceSpeed, smoke: true,
                        fps: sleeping ? 15 : nil)
        }
        .opacity(sleeping ? 0.5 : 1)
        .animation(.easeInOut(duration: 2), value: sleeping)
        .task(id: !showChat && voiceState == .idle && !sleeping) {
            if !showChat && voiceState == .idle && !sleeping { await music.listen() }
        }
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
        // Scroll up for what was said earlier; it rests on the newest line.
        ScrollView(showsIndicators: false) {
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
                // The newest four brighten toward the bottom; older ones sit dim.
                .opacity(max(0.4, 1 - 0.2 * Double(messages.count - 1 - i)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 520, minHeight: 300, alignment: .bottomLeading)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: 520, maxHeight: 300)
        .animation(.easeOut(duration: 0.3), value: messages)
        .padding(.horizontal, 0)
        .padding(.bottom, 24)
    }

    /// The screen's buttons, spoken (Oscar, 2026-09-17). She still answers
    /// the line; this only presses the button. No "unmute": a muted mic hears
    /// nothing, so that one stays a tap.
    /// She wakes: the sound, then the call, listening (Oscar, 2026-10-01),
    /// and her first words a line of Old Norse about victory (2026-10-02).
    private func summon() {
        guard !pet.running else { return }
        // Already summoned, she is here: the sound was her arrival.
        if !present { Awaken.play() }
        showChat = false
        live.muted = false
        let line = Self.victory.randomElement()!
        // The realm carves it in runes while she says it (2026-10-03).
        chantLine = line
        pet.begin(saying: [QueuedCommand(id: "awaken", text: line, show: nil)])
    }

    /// The line she is speaking as she arrives, for the realm to burn in.
    @State private var chantLine = ""

    /// Short, and real: the Edda and Ragnar's death-song.
    private static let victory = [
        "Sigrúnar skaltu kunna, ef þú vilt sigr hafa.",      // Sigrdrífumál 6
        "Orðstírr deyr aldregi, hveim er sér góðan getr.",   // Hávamál 76
        "Hjuggu vér með hjörvi.",                            // Krákumál
        "Hlæjandi skal ek deyja.",                           // Krákumál, the last line
    ]

    private func obey(_ text: String) {
        switch VoiceCommand(text) {
        // Duerme: she sleeps and the call ends. Vía: that, and the normal screen.
        case .sleep?: if pet.running { pet.toggleRunning() }
        case .leave?:
            if pet.running { pet.toggleRunning() }
            setPresentation(.base)
        case .transcript(let on)?: withAnimation { chrome = on }
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
        // Scrollable now (Oscar, 2026-10-01), so it keeps the call, not four lines.
        if messages.count > 80 { messages.removeFirst(messages.count - 80) }
    }
}

// MARK: - her screen

/// A page she put on screen, in the app's own sheet.
///
/// Her name over the room, with its flicker (see `ContentView.masthead`).
/// Its own view since 26.0: the flicker lived on ContentView, so every dip
/// of the tube, up to six a flicker every few seconds, re-ran the whole
/// screen's body and layout; now only the wordmark redraws.
private struct Masthead: View {
    @Binding var presentation: ContentView.Presentation
    /// The wordmark's flicker: a tube that is not quite well.
    @State private var flicker = 1.0

    var body: some View {
        let cyan = Skin.cyan
        // One line, not two: the title row is a row (Oscar, 2026-09-29). The
        // tagline drops out first when the window is narrow, as the
        // dashboard's own wordmark does.
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            // The title is the menu of versions (Oscar, 2026-10-01).
            Menu {
                Picker("Mode", selection: $presentation) {
                    ForEach(ContentView.Presentation.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Arisuへようこそ！")
                        // As tall as the button beside it: the title is the other half
                        // of that row, not a caption over it (Oscar, 2026-09-29).
                        .font(Skin.mono(26, .bold))
                        .tracking(4.5)
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Skin.mag)
                .shadow(color: Skin.mag.opacity(0.7 * flicker), radius: 12)
                .fixedSize()
            }
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

}

/// The three modes are the desk's decision (server/reader.py), mirroring
/// arisu-voice.js `drawPage` so the app and the web face show the same thing
/// for the same page: `frame` is the site itself in a web view, `reader` is
/// the text or the headlines the desk could read off it, and `tab` is the
/// honest note -- his logins cannot survive our web view, so it goes to Safari.
struct PageSheet: View {
    let page: ShowPage
    let close: () -> Void
    /// The page a demo puts in front; he switches with the picker.
    var front = 0
    /// Send what is open here to the desk's big screen (27.0); nil where
    /// there is no desk to send to. True when the desk took it.
    var toDesk: (([ScreenVisit]) async -> Bool)? = nil
    /// A demo showing the key as pressed; nothing is sent.
    var stagedSent = false
    @Environment(\.openURL) private var openURL
    @State private var sent: Bool?
    /// Which of several pages pushed at once is in front (26.0).
    @State private var at = 0

    private var pages: [ShowPage] { page.panels ?? [page] }
    private var shown: ShowPage { pages[min(at, pages.count - 1)] }

    var body: some View {
        NavigationStack {
            // Every page stays loaded and only the one in front shows, so
            // switching back does not reload a page or lose its place.
            ZStack {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    content(p).opacity(i == at ? 1 : 0).allowsHitTesting(i == at)
                }
            }
                .navigationTitle(shown.host ?? shown.url)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: close)
                    }
                    if pages.count > 1 {
                        // A screen given several pages at once ("put my habits and
                        // my health up", lain's screens.put): one switch with each
                        // page's title, in the order they were pushed.
                        ToolbarItem(placement: .principal) {
                            Picker("Page", selection: $at) {
                                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                                    Text(p.title?.isEmpty == false ? p.title! : (p.host ?? "Page \(i + 1)")).tag(i)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 520)
                        }
                    }
                    if let toDesk {
                        // What he is reading on the iPad, onto the big screen,
                        // every page of it in the same order (27.0). The page's
                        // own address, so the desk shows the site and not the
                        // iPad's reading of it.
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                guard !stagedSent, pages.allSatisfy({ $0.url.hasPrefix("http") }) else { return }
                                Task { sent = await toDesk(pages.map { ScreenVisit(url: $0.url, title: $0.title ?? $0.host ?? "") }) }
                            } label: {
                                // Words as well as the icon: a toolbar shows a Label's
                                // icon alone, and a bare monitor says nothing.
                                HStack(spacing: 6) {
                                    Image(systemName: sent == true ? "checkmark.rectangle" : "display")
                                    Text(sent == true ? "On the desk" : sent == false ? "Desk refused" : "To the desk")
                                }
                            }
                            .tint(sent == false ? .red : Skin.cyan)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Safari") { if let u = URL(string: shown.url) { openURL(u) } }
                    }
                }
        }
        .onChange(of: front, initial: true) { at = front }
        .onChange(of: stagedSent, initial: true) { _, on in if on { sent = true } }
    }

    @ViewBuilder private func content(_ page: ShowPage) -> some View {
        let heads = page.headlines ?? []
        let text = page.text ?? ""
        if page.mode == "frame" {
            WebPage(url: URL(string: page.url))
        } else if page.mode == "tab" || (heads.isEmpty && text.isEmpty) {
            note(page.mode == "tab"
                 ? "This one needs you signed in, so it opens in your own browser."
                 : (page.error ?? "I could not read anything off that page."), url: page.url)
        } else if !heads.isEmpty {
            List(Array(heads.enumerated()), id: \.offset) { _, head in
                Text(head)
            }
        } else {
            ScrollView { Text(text).padding() }
        }
    }

    private func note(_ line: String, url: String) -> some View {
        VStack(spacing: 16) {
            Text(line).multilineTextAlignment(.center)
            Button("Open in Safari") { if let u = URL(string: url) { openURL(u) } }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Put his pages on a screen without her (27.0, Backlog: "A screen command
/// (deck button, shortcut, /show) puts a view on a named screen without
/// her"). The pages are the ones her screen_show tool knows, by the same
/// addresses, so a page put up here and one she put up are the same push to
/// lain. This iPad and the desk are always offered; any other screen lain
/// holds a page for is offered too.
struct ScreenSheet: View {
    @ObservedObject var chat: Chat
    /// After a push to or a clear of `name`, so this iPad can follow its own
    /// screen at once rather than at its next four-second read.
    let changed: (String) -> Void
    let close: () -> Void
    /// Open what another screen shows in this iPad's page window, without
    /// changing that screen.
    let open: (ScreenState) -> Void
    /// What a demo stop puts on show: its pages picked, and whether it reads
    /// as sent. Nothing is ever written while this is set.
    var staged: DemoAct = .none

    static let pages: [(title: String, url: String, symbol: String)] = [
        ("Habits", "/systems/habits.html", "checklist"),
        ("Health", "/systems/health.html", "heart.text.square"),
        ("Diary", "/systems/diary.html", "book.closed"),
        ("Backlog", "/systems/backlog.html", "list.bullet.rectangle"),
        ("Agents", "/systems/agents.html", "person.2.wave.2"),
        ("Cookbook", "/systems/cookbook.html", "fork.knife"),
        ("Podcast", "/systems/podcast.html", "mic"),
        ("Lights", "/systems/lights.html", "lightbulb"),
        ("Chat", "/systems/chat.html", "bubble.left.and.text.bubble.right"),
        ("X-ray", "/systems/xray.html", "waveform.path.ecg"),
        ("Systems", "/systems/systems.html", "square.grid.2x2"),
        ("Deck", "/index.html", "rectangle.grid.3x2"),
        ("Microboard", "/systems/microboard/", "rectangle.split.3x3"),
    ]

    @State private var target = "desk"
    @State private var known: [ScreenState] = []
    /// In the order he picked them, which is the order lain lays them out.
    @State private var picked: [String] = []
    @State private var busy = false
    @State private var said: String?

    private var demoing: Bool { staged != .none }
    private var names: [String] {
        var seen = Set<String>()
        return (["ipad", "desk"] + known.compactMap(\.name)).filter { seen.insert($0).inserted }
    }
    private func label(_ name: String) -> String {
        switch name {
        case "ipad": return "This iPad"
        case "desk": return "Desk"
        default: return name
        }
    }
    private var holding: ScreenState? { demoing ? nil : known.first { $0.name == target } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Screen", selection: $target) {
                        ForEach(names, id: \.self) { Text(label($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(holding.map { "Shows now: " + $0.pages.map { $0.title.isEmpty ? $0.url : $0.title }
                                                   .joined(separator: ", ") }
                         ?? "Shows nothing from lain now.")
                        .font(Skin.mono(13)).foregroundStyle(Skin.off)
                    // The answer to a press, at the top where it is seen: the
                    // buttons sit below the fold of a long list.
                    if let said { Text(said).font(Skin.mono(13, .bold)).foregroundStyle(Skin.cyan) }
                    // What the desk shows, read here (27.0): the screen near
                    // him is the iPad, and the desk keeps its page.
                    if let h = holding, target != ContentView.screenName {
                        Button { open(h) } label: {
                            Label("Open it here", systemImage: "ipad.landscape").foregroundStyle(Skin.cyan)
                        }
                    }
                } header: { Text("Which screen") }
                Section {
                    ForEach(Self.pages, id: \.url) { p in
                        Button { toggle(p.url) } label: {
                            HStack {
                                Label(p.title, systemImage: p.symbol).foregroundStyle(.white)
                                Spacer()
                                if let i = picked.firstIndex(of: p.url) {
                                    Text("\(i + 1)").font(Skin.mono(14, .bold)).foregroundStyle(Skin.mag)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Pages, up to six, side by side in the order you pick them")
                }
                Section {
                    Button { Task { await putUp() } } label: {
                        Label("Put up on " + label(target), systemImage: "rectangle.badge.plus")
                            .font(Skin.mono(15, .bold)).foregroundStyle(picked.isEmpty ? Skin.off : Skin.cyan)
                    }
                    .disabled(picked.isEmpty || busy)
                    Button(role: .destructive) { Task { await clear() } } label: {
                        Label("Clear " + label(target), systemImage: "rectangle.slash")
                    }
                    .disabled(busy || (!demoing && holding == nil))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Grid(tint: Skin.cyan).ignoresSafeArea())
            .navigationTitle("Put on a screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close).tint(Skin.cyan) }
            }
            .task { if !demoing { known = await chat.screens() } }
            .onChange(of: staged, initial: true) { _, act in
                guard act != .none else { return }
                target = "desk"
                picked = ["/systems/habits.html", "/systems/health.html"]
                said = act == .screensSent ? "Habits and Health are on Desk. (A demo: nothing was sent.)" : nil
            }
        }
        .preferredColorScheme(.dark)
    }

    private func toggle(_ url: String) {
        guard !demoing else { return }
        said = nil
        if let i = picked.firstIndex(of: url) { picked.remove(at: i) }
        else if picked.count < 6 { picked.append(url) }
    }

    private func putUp() async {
        guard !demoing else { return }
        busy = true
        defer { busy = false }
        let visits = picked.compactMap { u in Self.pages.first { $0.url == u }.map { ScreenVisit(url: u, title: $0.title) } }
        let names = visits.map(\.title).joined(separator: " and ")
        guard await chat.put(target, pages: visits) != nil else {
            said = "The desk did not take it. Nothing changed."
            return
        }
        said = names + (visits.count > 1 ? " are" : " is") + " on " + label(target) + "."
        changed(target)
        known = await chat.screens()
    }

    private func clear() async {
        guard !demoing else { return }
        busy = true
        defer { busy = false }
        said = await chat.clearScreen(target) ? label(target) + " is clear." : label(target) + " held nothing."
        changed(target)
        known = await chat.screens()
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
            // The Record panel's log row: a lit bar on the speaker's side,
            // a square box, a thin neon edge (Oscar, 2026-09-30).
            let ink = mine ? mineColor : voice
            Text(conversationLinks(speaker(mine) + text))
                .font(Skin.mono(18, .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .plate { Rectangle().fill(solid ? Color.black.opacity(0.62) : ink.opacity(0.08)) }
                .edge { Rectangle().stroke(ink.opacity(0.45), lineWidth: 1) }
                .edge(alignment: mine ? .trailing : .leading) {
                    Rectangle().fill(ink).frame(width: 3).shadow(color: ink, radius: 4)
                }
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
        Text(conversationLinks(speaker(mine) + text))
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
    case transcript(Bool), settings(Bool), sleep, leave

    init?(_ line: String) {
        let t = line.lowercased()
        func has(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        // One word said on its own, her name in front allowed, so a sentence
        // that merely contains it does not end the call (Oscar, 2026-10-01).
        func alone(_ w: String) -> Bool { has(#"^\W*(arisu\W*)?"# + w + #"\W*$"#) }
        if alone("duerme") { self = .sleep; return }
        if alone("v[ií]a") { self = .leave; return }
        let on = #"\b(show|open|turn on|switch on)\b"#, off = #"\b(hide|close|turn off|switch off)\b"#
        let chat = #"\b(transcript|subtitles|captions|chat)\b"#
        if has(on + ".{0,12}" + chat) { self = .transcript(true) }
        else if has(off + ".{0,12}" + chat) { self = .transcript(false) }
        else if has(on + ".{0,12}\\bsettings\\b") { self = .settings(true) }
        else if has(off + ".{0,12}\\bsettings\\b") { self = .settings(false) }
        else { return nil }
    }
}

/// The one place her level and the Mac's music are watched. Everything else
/// on screen is built without them, so a call or a song moves her face and
/// nothing else is rebuilt (18.0).
struct Metered<Content: View>: View {
    @ObservedObject var meter: Meter
    @ObservedObject var music: MacMusic
    @ViewBuilder let content: (Double, Double) -> Content
    var body: some View { content(Double(meter.level), music.level) }
}
