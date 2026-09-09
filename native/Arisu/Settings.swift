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
    @State private var voices: [String] = []
    @State private var failed = false
    @State private var notesPush: Task<Void, Never>?

    private let brain = Brain()
    private let accent = Color(red: 0.27, green: 0.90, blue: 0.97)

    var body: some View {
        NavigationStack {
            Group {
                if draft != nil { form } else if failed { retry } else { loading }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("How she is")
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

    private func reload() async {
        failed = false
        do {
            let got = try await brain.persona()
            voices = got.voices ?? [got.voice]
            draft = got
        } catch {
            failed = true
        }
    }
}
