import SwiftUI

/// What she is like, adjustable from the couch.
///
/// The dials are hers as the desk holds them, not the app's: everything here
/// reads and writes `/arisu/persona` on architect, so the settings survive a
/// reinstall and apply to whatever device connects next. They take effect on
/// her next connection, because her instructions are assembled when the
/// session is minted -- which is why saving offers to reconnect.
///
/// Only tone, length, voice and a note in his own words. Her tools, her
/// memory, and the rules that keep her straight about his data are not here
/// and are not reachable from here.
struct SettingsSheet: View {
    @ObservedObject var pet: Pet
    @Environment(\.dismiss) private var dismiss

    @State private var persona: Persona?
    @State private var failed = false
    @State private var saving = false

    private let brain = Brain()
    private let accent = Color(red: 0.27, green: 0.90, blue: 0.97)

    var body: some View {
        NavigationStack {
            Group {
                if let persona { form(persona) } else if failed { retry } else { loading }
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

    private func form(_ p: Persona) -> some View {
        Form {
            Section {
                dial("Warmth", "Friendly distance", "Openly fond",
                     value: binding(\.warmth, key: "warmth"))
                dial("Playfulness", "Earnest", "Teasing",
                     value: binding(\.playfulness, key: "playfulness"))
                dial("Brevity", "Room to talk", "One short sentence",
                     value: binding(\.brevity, key: "brevity"))
            } header: {
                header("Manner")
            }

            Section {
                Picker("Voice", selection: binding(\.voice, key: "voice")) {
                    ForEach(p.voices ?? [p.voice], id: \.self) { name in
                        Text(name.capitalized).tag(name)
                    }
                }
                .font(.system(size: 19))
            } header: {
                header("Voice")
            } footer: {
                footer("Changing the voice needs a reconnect. Pause and start "
                       + "her again, or wait for the session to lapse.")
            }

            Section {
                TextEditor(text: binding(\.notes, key: "notes"))
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
        .disabled(saving)
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

    private func dial(_ title: String, _ low: String, _ high: String,
                      value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 19, weight: .medium))
            Slider(value: value, in: 0...1)
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

    /// Every edit is written straight through as a one-key patch. There is no
    /// Save button on purpose: two settings screens, or a settings screen and
    /// a spoken instruction, must not be able to overwrite each other with a
    /// whole stale object.
    private func binding<V>(_ path: WritableKeyPath<Persona, V>,
                            key: String) -> Binding<V> {
        Binding(
            get: { persona![keyPath: path] },
            set: { newValue in
                persona?[keyPath: path] = newValue
                Task { await push([key: newValue]) }
            })
    }

    private func push(_ patch: [String: Any]) async {
        saving = true
        defer { saving = false }
        if let got = try? await brain.setPersona(patch) { persona = got }
    }

    private func reload() async {
        failed = false
        do { persona = try await brain.persona() } catch { failed = true }
    }
}
