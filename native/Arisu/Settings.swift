import SwiftUI

/// What she is like, adjustable from the couch.
///
/// The dials are hers as the desk holds them, not the app's: everything here
/// reads and writes `/arisu/persona` on architect, so the settings survive a
/// reinstall and apply to whatever device connects next.
///
/// Only tone, length, voice and a note in his own words. Her tools, her
/// memory, and the rules that keep her straight about his data are not here
/// and are not reachable from here.
struct SettingsSheet: View {
    @ObservedObject var pet: Pet
    @ObservedObject var live: Live
    @Environment(\.dismiss) private var dismiss

    /// The edit in progress, held locally.
    ///
    /// The first version bound each control straight through to a POST and
    /// then replaced the whole object with whatever came back. Dragging a
    /// slider fires that dozens of times a second, and every reply snapped the
    /// knob to a value from a request two moves ago -- it read as a slider
    /// that stuttered and would not follow the thumb. Now the control owns the
    /// value while he is touching it, and the desk hears about it when he
    /// lets go.
    @State private var draft: Persona?
    /// Everyone the desk knows about, and who is on it. Held here rather than
    /// on the pet because it is only ever looked at on this screen.
    @State private var cast: Cast?
    @State private var switching = false
    @State private var voices: [String] = []
    @State private var failed = false
    @State private var notesPush: Task<Void, Never>?
    @State private var previewing = false
    @AppStorage(Live.geminiKey) private var geminiVoice = false
    @AppStorage("arisu.faceStyle") private var faceStyle = FaceStyle.ribbon.rawValue
    /// Bubbles or terminal lines, for her subtitles and the typed chat alike.
    @AppStorage("arisu.bubbles.voice") private var voiceBubbles = true
    @AppStorage("arisu.bubbles.chat") private var chatBubbles = true
    @AppStorage("arisu.faceScale") private var faceScale = 1.0
    @AppStorage("arisu.faceBloom") private var faceBloom = 1.0
    @AppStorage("arisu.faceSpeed") private var faceSpeed = 1.0
    /// Where she stands on the screen, in points from the middle.
    @AppStorage("arisu.faceX") private var faceX = 0.0
    @AppStorage("arisu.faceY") private var faceY = 0.0
    @AppStorage(Skin.freeFormKey) private var freeForm = false
    @AppStorage(Skin.smokeKey) private var smokeAmount = 1.0
    /// The face card in the middle of the deck.
    @State private var deckAt: String?
    @AppStorage(Night.fromKey) private var nightFrom = Night.from
    @AppStorage(Night.toKey) private var nightTo = Night.to

    private let brain = Brain()
    private let accent = Skin.cyan

    var body: some View {
        NavigationStack {
            Group {
                if draft != nil { form } else if failed { retry } else { loading }
            }
            .background(Grid(tint: Skin.cyan).ignoresSafeArea())
            .fontDesign(.monospaced)
            .navigationTitle(draft?.name.map { "How \($0) is" } ?? "How she is")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 20, weight: .semibold))
                        .tint(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await reload() }
        .onDisappear {
            // A note he was still typing when he closed the sheet is a note he
            // meant. Fire the pending write rather than dropping it.
            notesPush?.cancel()
            if let notes = draft?.notes {
                Task { try? await brain.setPersona(["notes": notes]) }
            }
        }
    }

    private var loading: some View {
        ProgressView().tint(accent).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var retry: some View {
        VStack(spacing: 18) {
            Text("The desk did not answer.")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.7))
            Button("Try again") { Task { await reload() } }
                .font(.system(size: 20, weight: .semibold))
                .tint(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var form: some View {
        ScrollViewReader { proxy in
        Form {
            if let cast, cast.characters.count > 1 { castSection(cast) }

            Section {
                faceDeck
                    .listRowInsets(EdgeInsets())
                dial("Size", $faceScale, 0.5...1.8)
                dial("Glow", $faceBloom, 0...2.2)
                dial("Pace", $faceSpeed, 0.3...2.0)
                if freeForm { dial("Smoke", $smokeAmount, 0...2) }
                dial("Left / right", $faceX, -400...400, "%.0f")
                dial("Up / down", $faceY, -400...400, "%.0f")
                Button("Reset") {
                    faceScale = 1; faceBloom = 1; faceSpeed = 1; smokeAmount = 1
                    faceX = 0; faceY = 0
                }
                .font(.system(size: 19))
            } header: {
                header("Face")
            } footer: {
                footer("Roll the deck to choose. The colour is what she is doing, "
                       + "the movement is her voice."
                       + (freeForm ? " Smoke 0 is none." : ""))
            }

            Section {
                Picker("Voice", selection: Binding(
                    get: { draft?.voice ?? "" },
                    set: { pickVoice($0) })) {
                    ForEach(voices, id: \.self) { name in
                        Text(name.capitalized).tag(name)
                    }
                }
                .font(.system(size: 19))
                Button {
                    Task { await preview() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: previewing ? "waveform" : "play.circle.fill")
                            .font(.system(size: 24))
                        Text(previewing ? "Playing..." : "Play sample")
                            .font(.system(size: 19, weight: .medium))
                        Spacer()
                        if let line = draft?.sample, !previewing {
                            Text("\u{201C}" + line + "\u{201D}")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .disabled(previewing || live.paused)
                // Gemini Live, behind a switch until it is proven on this iPad
                // (stage 3 of arisu/GEMINI-LIVE-PLAN.md, 2026-10-07).
                Toggle("Gemini voice (test)", isOn: Binding(
                    get: { geminiVoice },
                    set: { on in
                        geminiVoice = on
                        Task { await live.reconnect() }
                    }))
                .font(.system(size: 19))
            } header: {
                header("Voice")
            } footer: {
                // The voice is fixed to the session when it is minted, so it
                // cannot change under her mid-sentence.
                footer((live.paused ? "She is paused: start the conversation to hear her. " : "")
                       + "She reconnects to change voice or engine, so she goes "
                       + "quiet for a moment. The voice applies only with Gemini off.")
            }

            Section {
                dial("Warmth", "Friendly distance", "Openly fond",
                     get: { $0.warmth }, set: { $0.warmth = $1 }, key: "warmth")
                dial("Playfulness", "Earnest", "Teasing",
                     get: { $0.playfulness }, set: { $0.playfulness = $1 },
                     key: "playfulness")
                dial("Brevity", "Room to talk", "One short sentence",
                     get: { $0.brevity }, set: { $0.brevity = $1 }, key: "brevity")
                VStack(alignment: .leading, spacing: 6) {
                    Text("In your own words").font(.system(size: 19, weight: .medium))
                    TextEditor(text: Binding(
                        get: { draft?.notes ?? "" },
                        set: { typeNotes($0) }))
                        .font(.system(size: 19))
                        .frame(minHeight: 130)
                        .scrollContentBackground(.hidden)
                }
                .padding(.vertical, 6)
            } header: {
                header("Manner")
            } footer: {
                footer("Takes effect on her next answer. Your own words outrank "
                       + "the dials and go into her instructions as typed.")
            }

            Section {
                // Subtitles are read from across the room and the thread at
                // arm's length, so each has its own (Oscar, 2026-09-29).
                Picker("Subtitles", selection: $voiceBubbles) {
                    Text("Bubbles").tag(true)
                    Text("Terminal").tag(false)
                }
                .font(.system(size: 19))
                Picker("Chat", selection: $chatBubbles) {
                    Text("Bubbles").tag(true)
                    Text("Terminal").tag(false)
                }
                .font(.system(size: 19))
            } header: {
                header("Messages")
            } footer: {
                footer("Bubbles: hers left, yours right. Terminal: every line "
                       + "on the left, the way a log reads.")
            }

            Section {
                Stepper(value: $nightFrom, in: 0...23) {
                    Text("Asleep from " + String(format: "%02d:00", nightFrom)).font(.system(size: 17, weight: .medium))
                }
                Stepper(value: $nightTo, in: 0...23) {
                    Text("Awake at " + String(format: "%02d:00", nightTo)).font(.system(size: 17, weight: .medium))
                }
            } header: {
                header("Night").id("night")
            } footer: {
                footer(nightFrom == nightTo
                       ? "Off: she listens for 醒来 day and night."
                       : "Until morning she does not listen for 醒来 and her face "
                         + "sleeps, dim and slow. Holding Singularity or tapping the "
                         + "microphone still brings her. The same hour twice "
                         + "switches night off.")
            }
        }
        .tint(accent)
        #if DEBUG
        // For checking a section in the simulator, where nothing can scroll:
        // `simctl launch … -arisu.settings YES -arisu.settingsAt night`.
        .task {
            guard let at = UserDefaults.standard.string(forKey: "arisu.settingsAt") else { return }
            try? await Task.sleep(for: .seconds(1))
            proxy.scrollTo(at, anchor: .top)
        }
        #endif
        }
    }

    /// The faces in one row that rolls like a drum (Oscar, 2026-10-08): the
    /// one in the middle faces him and is the one she wears, the rest turn
    /// away. Scroll or tap to choose. Each card is drawn with his dials, so
    /// the deck is also the preview of them.
    private var faceDeck: some View {
        GeometryReader { g in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(FaceStyle.offered) { style in
                        let on = style.rawValue == faceStyle
                        VStack(spacing: 8) {
                            VoiceVisual(style: style, state: .speaking, amplitude: 0.5,
                                        tint: Skin.cyan, scale: faceScale, bloom: faceBloom,
                                        speed: faceSpeed, smoke: freeForm ? smokeAmount : 0)
                                .frame(width: Self.card, height: Self.card)
                                .background(Skin.void)
                                .clipShape(RoundedRectangle(cornerRadius: Skin.radius))
                                .edge { RoundedRectangle(cornerRadius: Skin.radius)
                                    .stroke(on ? Skin.mag : Color.white.opacity(0.18),
                                            lineWidth: on ? 2 : 1) }
                            Text(style.label)
                                .font(Skin.mono(13, on ? .semibold : .regular))
                                .foregroundStyle(on ? Skin.mag : Skin.ink)
                        }
                        .frame(width: Self.card + 24)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { deckAt = style.rawValue } }
                        .scrollTransition(.interactive.threshold(.centered), axis: .horizontal) { c, phase in
                            c.rotation3DEffect(.degrees(phase.value * -50), axis: (0, 1, 0),
                                               perspective: 0.5)
                                .scaleEffect(1 - abs(phase.value) * 0.28)
                                .opacity(1 - abs(phase.value) * 0.55)
                        }
                        .id(style.rawValue)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (g.size.width - Self.card - 24) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $deckAt, anchor: .center)
        }
        .frame(height: Self.card + 56)
        .padding(.vertical, 8)
        .onAppear { deckAt = faceStyle }
        .onChange(of: deckAt) { if let deckAt { faceStyle = deckAt } }
    }

    private static let card: CGFloat = 200

    private func dial(_ title: String, _ value: Binding<Double>,
                      _ range: ClosedRange<Double>, _ format: String = "%.2f") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 19, weight: .medium))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Slider(value: value, in: range)
        }
        .padding(.vertical, 6)
    }

    /// Who is on the desk.
    ///
    /// A picker and not a list of cards: this is one choice with a small
    /// number of answers, and it is the first thing on the screen because
    /// everything under it describes whoever is picked. Changing it reloads
    /// the whole form -- the dials, the voice and the note all belong to the
    /// character, not to the app.
    private func castSection(_ cast: Cast) -> some View {
        Section {
            Picker("Who", selection: Binding(
                get: { cast.active },
                set: { pick($0) })) {
                ForEach(cast.ordered, id: \.id) { row in
                    Text(row.persona.name ?? row.id.capitalized).tag(row.id)
                }
            }
            .font(.system(size: 19))
            .disabled(switching)
        } header: {
            header("On the desk")
        } footer: {
            footer(switching
                   ? "Handing over..."
                   : "Each of them has their own face, voice and manner. She "
                     + "reconnects to change, so there is a quiet moment while "
                     + "they swap.")
        }
    }

    /// Switch character, then reload the form against whoever answered.
    ///
    /// The reload is not optional. The dials below are bound to `draft`, which
    /// is the old character's settings until this returns -- leaving them would
    /// show Chopper's name over Arisu's warmth, and the first slider he touched
    /// would write her value onto him.
    private func pick(_ id: String) {
        guard !switching, id != cast?.active else { return }
        switching = true
        Task {
            await pet.switchCharacter(to: id)
            await reload()
            switching = false
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(accent.opacity(0.75))
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
    }

    /// One dial. `onEditingChanged` is the whole point: the value moves freely
    /// under his thumb and is written once, when he lifts it.
    private func dial(_ title: String, _ low: String, _ high: String,
                      get: @escaping (Persona) -> Double,
                      set: @escaping (inout Persona, Double) -> Void,
                      key: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 19, weight: .medium))
            Slider(value: Binding(
                get: { draft.map(get) ?? 0.5 },
                set: { value in if draft != nil { set(&draft!, value) } }),
                in: 0...1,
                onEditingChanged: { editing in
                    guard !editing, let draft else { return }
                    Task { try? await brain.setPersona([key: get(draft)]) }
                })
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 6)
    }

    // MARK: - talking to the desk

    private func pickVoice(_ name: String) {
        guard var next = draft, next.voice != name else { return }
        next.voice = name
        draft = next
        Task {
            _ = try? await brain.setPersona(["voice": name])
            // Instructions and voice are both fixed at mint time, so a live
            // session keeps the old one until it is replaced.
            await live.reconnect()
        }
    }

    /// Typing is not a commit. Written a beat after he stops, so a paragraph
    /// is one request rather than one per keystroke.
    private func typeNotes(_ text: String) {
        guard draft != nil else { return }
        draft!.notes = text
        notesPush?.cancel()
        notesPush = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await brain.setPersona(["notes": text])
        }
    }

    /// Have her say the sample line as she is currently set.
    ///
    /// Any pending edit is written first: the manner is baked into her session
    /// when it is minted, so previewing before the desk has the new value
    /// would demonstrate the old one.
    private func preview() async {
        guard let draft else { return }
        previewing = true
        defer { previewing = false }
        notesPush?.cancel()
        let got = try? await brain.setPersona([
            "warmth": draft.warmth, "playfulness": draft.playfulness,
            "brevity": draft.brevity, "notes": draft.notes])
        if let got { self.draft = got }
        await live.preview(got?.sample ?? draft.sample ?? "")
    }

    private func reload() async {
        failed = false
        do {
            // Both, because the form shows one character's settings under a
            // picker of all of them, and a picker that lists someone the
            // dials do not describe is worse than no picker.
            async let persona = brain.persona()
            async let everyone = brain.cast()
            let got = try await persona
            voices = got.voices ?? [got.voice]
            draft = got
            cast = try? await everyone
        } catch {
            failed = true
        }
    }
}
