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
