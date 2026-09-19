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
    @AppStorage("arisu.meter") private var showMeter = true

    private let brain = Brain()
    private let accent = Color(red: 0.27, green: 0.90, blue: 0.97)

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
                Toggle("Live2D face", isOn: $live2dFace)
                    .font(.system(size: 19))
                Toggle("Moving bars at the bottom", isOn: $showMeter)
                    .font(.system(size: 19))
                if live2dFace { modelGrid }
            } header: {
                header("Face")
            } footer: {
                footer("Draws her as a moving Live2D model, loaded from the desk. "
                       + "The model is saved to the character, so the web page "
                       + "shows the same one. If the desk cannot be reached, "
                       + "the portrait comes back.")
            }

            if live2dFace { glowSection }

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
            : (pet.face == "chopper" ? "Natori" : "Haru")
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
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
