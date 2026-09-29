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
    /// Shared with `ContentView`, which hands it to the face. A preference of
    /// this screen, not of the character, so it lives on the device.
    @AppStorage("arisu.live2d") private var live2dFace = true
    @AppStorage("arisu.faceStyle") private var faceStyle = FaceStyle.ribbon.rawValue
    @AppStorage("arisu.meter") private var showMeter = true
    /// Bubbles or terminal lines, for her subtitles and the typed chat alike.
    @AppStorage("arisu.bubbles.voice") private var voiceBubbles = true
    @AppStorage("arisu.bubbles.chat") private var chatBubbles = true
    @AppStorage("arisu.faceScale") private var faceScale = 1.0
    @AppStorage("arisu.faceBloom") private var faceBloom = 1.0
    @AppStorage("arisu.faceSpeed") private var faceSpeed = 1.0
    /// Where she stands on the screen, in points from the middle.
    @AppStorage("arisu.faceX") private var faceX = 0.0
    @AppStorage("arisu.faceY") private var faceY = 0.0

    private let brain = Brain()
    private let accent = Skin.cyan

    var body: some View {
        NavigationStack {
            Group {
                if draft != nil { form } else if failed { retry } else { loading }
            }
            .background(Color.black.ignoresSafeArea())
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
        Form {
            if let cast, cast.characters.count > 1 { castSection(cast) }

            Section {
                // A picture of a person, or a picture of a voice. Shown as
                // moving tiles rather than as a list of words: the names mean
                // nothing until you have seen them (Oscar, 2026-09-29).
                faceStyleGrid
                if faceStyle == FaceStyle.portrait.rawValue {
                    Toggle("Live2D face", isOn: $live2dFace)
                        .font(.system(size: 19))
                }
                Toggle("Moving bars at the bottom", isOn: $showMeter)
                    .font(.system(size: 19))
                if faceStyle == FaceStyle.portrait.rawValue && live2dFace { modelGrid }
            } header: {
                header("Face")
            } footer: {
                footer("Portrait draws her as herself -- a still, or a moving "
                       + "Live2D model loaded from the desk, saved to the "
                       + "character so the web page shows the same one. The "
                       + "spheres draw her voice instead: the state is the "
                       + "colour, her level is the movement, and they need "
                       + "nothing from the desk.")
            }

            positionSection

            Section {
                // One preference for both was the wrong shape: subtitles are
                // read from across the room and the thread at arm's length
                // (Oscar, 2026-09-29).
                Picker("In the room", selection: $voiceBubbles) {
                    Text("Bubbles").tag(true)
                    Text("Terminal").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("In the chat", selection: $chatBubbles) {
                    Text("Bubbles").tag(true)
                    Text("Terminal").tag(false)
                }
                .pickerStyle(.segmented)
            } header: {
                header("Messages")
            } footer: {
                footer("How each mode draws the conversation, separately: her "
                       + "subtitles over her face, and the typed thread. "
                       + "Bubbles are hers on the left and yours on the right; "
                       + "terminal is one line each.")
            }

            if isVisual { visualSection }
            // The glow sliders light the portrait and the Live2D model. A
            // voice visual carries its own light, so they would be four dead
            // controls there (Oscar, 2026-09-29).
            if !isVisual && live2dFace { glowSection }

            Section {
                dial("Warmth", "Friendly distance", "Openly fond",
                     get: { $0.warmth }, set: { $0.warmth = $1 }, key: "warmth")
                dial("Playfulness", "Earnest", "Teasing",
                     get: { $0.playfulness }, set: { $0.playfulness = $1 },
                     key: "playfulness")
                dial("Brevity", "Room to talk", "One short sentence",
                     get: { $0.brevity }, set: { $0.brevity = $1 }, key: "brevity")
            } header: {
                header("Manner")
            } footer: {
                footer("Takes effect on her next answer.")
            }

            Section {
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
            } footer: {
                footer(live.paused
                       ? "She is paused. Start the conversation to hear her."
                       : "She reconnects to say it, so she goes quiet for a "
                         + "moment first. Her voice, her manner, as set above.")
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
            } header: {
                header("Voice")
            } footer: {
                // The voice is fixed to the session when it is minted, so it
                // cannot change under her mid-sentence. Reconnecting is the
                // only way to hear it, and doing that by hand was the first
                // thing he tried and the first thing that looked broken.
                footer("She reconnects to change voice, so she will go quiet "
                       + "for a moment.")
            }

            Section {
                TextEditor(text: Binding(
                    get: { draft?.notes ?? "" },
                    set: { typeNotes($0) }))
                    .font(.system(size: 19))
                    .frame(minHeight: 130)
                    .scrollContentBackground(.hidden)
            } header: {
                header("In your own words")
            } footer: {
                footer("Anything here outranks the dials above. It is written "
                       + "into her instructions exactly as you type it.")
            }
        }
        .tint(accent)
    }

    /// The models as pictures, not names -- the same stills the web panel
    /// shows, served by the desk. The character's choice is saved there.
    private var modelGrid: some View {
        let current = FaceView.models.contains(pet.model) ? pet.model
            : (pet.face == "chopper" ? "Mao" : "Haru")
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                         spacing: 10) {
            ForEach(FaceView.models, id: \.self) { m in
                Button { pickModel(m) } label: {
                    VStack(spacing: 4) {
                        AsyncImage(url: Brain.base.appendingPathComponent("live2d/thumbs/\(m).png")) {
                            $0.resizable().scaledToFit()
                        } placeholder: { Color.white.opacity(0.05) }
                        .aspectRatio(3 / 4, contentMode: .fit)
                        Text(m).font(.system(size: 14))
                            .foregroundStyle(m == current ? .white : .white.opacity(0.6))
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(m == current ? accent.opacity(0.12) : Color.white.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(m == current ? accent : .white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func pickModel(_ m: String) {
        guard m != pet.model else { return }
        Task {
            _ = try? await brain.setPersona(["model": m])
            await pet.refreshCast()
        }
    }

    /// The ten voice visuals and the portrait, each one moving, with the
    /// chosen one ringed. Every tile cycles the four states on its own clock,
    /// so a glance shows both the colour and the movement.
    private var faceStyleGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
            ForEach(FaceStyle.allCases) { style in
                let on = style.rawValue == faceStyle
                Button { faceStyle = style.rawValue } label: {
                    VStack(spacing: 6) {
                        FacePreview(style: style)
                            .overlay(RoundedRectangle(cornerRadius: Skin.radius)
                                .stroke(on ? Skin.mag : Color.white.opacity(0.18),
                                        lineWidth: on ? 2 : 1))
                        Text(style.label)
                            .font(Skin.mono(11, on ? .semibold : .regular))
                            .foregroundStyle(on ? Skin.mag : Skin.ink)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    /// Is she drawn as a voice visual rather than as a picture of a person.
    private var isVisual: Bool {
        (FaceStyle(rawValue: faceStyle) ?? .ribbon) != .portrait
    }

    /// The three dials that shape a drawn face. Size and pace are the ones he
    /// will actually move; the glow is here because the old glow sliders only
    /// ever reached the portrait.
    private var visualSection: some View {
        Section {
            dial("Size", $faceScale, 0.5...1.8)
            dial("Glow", $faceBloom, 0...2.2)
            dial("Pace", $faceSpeed, 0.3...2.0)
            Button("Back to the middle") { faceScale = 1; faceBloom = 1; faceSpeed = 1 }
                .font(.system(size: 19))
        } header: {
            header("The animation")
        } footer: {
            footer("How big she is drawn, how hard she glows, and how fast "
                   + "everything moves. The state still picks the colour and "
                   + "the movement; these only scale them.")
        }
    }

    private func dial(_ title: String, _ value: Binding<Double>,
                      _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 19, weight: .medium))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Slider(value: value, in: range)
        }
        .padding(.vertical, 6)
    }

    /// Where she stands on the screen. Kept on the device, not on the
    /// character: her face is a square tile in the middle of whatever screen
    /// is showing it, and the iPad on the desk and a phone on a shelf want
    /// different answers (Oscar, 2026-09-26).
    private var positionSection: some View {
        Section {
            positionDial("Left / right", $faceX)
            positionDial("Up / down", $faceY)
            Button("Put her back in the middle") { faceX = 0; faceY = 0 }
                .font(.system(size: 19))
        } header: {
            header("Where she stands")
        } footer: {
            footer("Moves her on the screen. The light and the ground stay "
                   + "where they are.")
        }
    }

    private func positionDial(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 19, weight: .medium))
                Spacer()
                Text(String(Int(value.wrappedValue)))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Slider(value: value, in: -400...400, step: 4)
        }
        .padding(.vertical, 6)
    }

    /// The spotlight behind the model. The light moves under his thumb, and
    /// the desk hears once he lets go. Defaults mirror cues.js.
    private var glowSection: some View {
        Section {
            glowDial("Strength", \.strength, 1.5, 0...4, "Off", "Bright")
            glowDial("Size", \.size, 1.3, 0.4...3, "Tight", "Wide")
            glowDial("Left / right", \.x, 54, 0...100, "Left", "Right")
            glowDial("Up / down", \.y, 42, 0...100, "Top", "Bottom")
            Button("Reset the glow") {
                pet.glow = Persona.Glow(strength: 1.5, size: 1.3, x: 54, y: 42)
                saveGlow()
            }
            .font(.system(size: 19))
        } header: {
            header("Glow")
        } footer: {
            footer("The light behind her. Its colour follows what she is doing.")
        }
    }

    private func glowDial(_ title: String, _ key: WritableKeyPath<Persona.Glow, Double?>,
                          _ fallback: Double, _ range: ClosedRange<Double>,
                          _ low: String, _ high: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 19, weight: .medium))
            Slider(value: Binding(get: { pet.glow[keyPath: key] ?? fallback },
                                  set: { pet.glow[keyPath: key] = $0 }),
                   in: range,
                   onEditingChanged: { if !$0 { saveGlow() } })
            HStack { Text(low); Spacer(); Text(high) }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 6)
    }

    private func saveGlow() {
        let g = pet.glow
        let patch = ["strength": g.strength ?? 1.5, "size": g.size ?? 1.3,
                     "x": g.x ?? 54, "y": g.y ?? 42]
        Task { try? await brain.setPersona(["glow": patch]) }
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
            try? await brain.setPersona(["voice": name])
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
            try? await brain.setPersona(["notes": text])
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
