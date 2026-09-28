import SwiftUI

/// Add, change or remove one button.
///
/// One form per action type, showing only the fields that type has: a `shell`
/// button asks for a command and an `open` button asks for a URL, and neither
/// is offered the other's field. A `compound` -- four of the pad's buttons were
/// compounds -- is shown but not taken apart: its steps come back to the Mac
/// exactly as they left, and rebuilding a multi-step action through a phone
/// form is not something he asked for.
struct DeckEditor: View {
    @State var button: DeckButton
    let isNew: Bool
    let groups: [String]
    let save: (DeckButton) -> Void
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    private let accent = Skin.cyan

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Label", $button.label)
                    field("Icon", Binding(get: { button.icon },
                                          set: { button.icon = $0 }), hint: "one emoji")
                    Picker("Group", selection: $button.group) {
                        ForEach(groups, id: \.self) { Text($0).tag($0) }
                        if !groups.contains(button.group) {
                            Text(button.group).tag(button.group)
                        }
                    }
                    if isNew { field("Id", $button.id, hint: "group.key") }
                } header: { head("The button") }

                Section {
                    Picker("Does", selection: $button.action.type) {
                        ForEach(DeckAction.types, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(button.action.type == "compound")
                    actionFields
                } header: { head("What it does") } footer: {
                    foot(button.action.type == "compound"
                         ? "Several steps, set on the Mac in buttons.json. The steps "
                           + "go back untouched."
                         : "Runs on the MacBook as you, the moment you press the button.")
                }

                if !isNew {
                    Section {
                        Button("Remove this button", role: .destructive) { confirmRemove = true }
                            .font(.system(size: 19))
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isNew ? "New button" : button.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(button); dismiss() }
                        .font(.system(size: 19, weight: .semibold))
                        .tint(accent)
                        .disabled(button.id.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Remove \(button.label)?", isPresented: $confirmRemove,
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) { remove(); dismiss() }
                Button("Keep it", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .tint(accent)
    }

    @ViewBuilder private var actionFields: some View {
        switch button.action.type {
        case "shell":
            multiline("Command", opt($button.action.cmd))
        case "applescript":
            multiline("AppleScript", opt($button.action.script))
        case "open":
            field("URL, app or folder", opt($button.action.url))
        case "keys":
            field("Shortcut", opt($button.action.keys), hint: "cmd+shift+t")
        case "text":
            multiline("Text", opt($button.action.text))
            Toggle("Type it into the front app", isOn: Binding(
                get: { button.action.paste ?? false },
                set: { button.action.paste = $0 }))
        case "notify":
            field("Title", opt($button.action.title))
            field("Text", opt($button.action.text))
        case "http":
            Picker("Method", selection: Binding(
                get: { button.action.method ?? "GET" },
                set: { button.action.method = $0 })) {
                ForEach(["GET", "POST", "PUT", "DELETE"], id: \.self) { Text($0).tag($0) }
            }
            field("URL", opt($button.action.url))
        case "compound":
            Text("\(button.action.steps?.count ?? 0) steps")
                .font(.system(size: 17, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        default:
            EmptyView()
        }
    }

    /// An optional string as a field can bind to: empty means absent, so a
    /// cleared field is omitted from the JSON rather than sent as "".
    private func opt(_ source: Binding<String?>) -> Binding<String> {
        Binding(get: { source.wrappedValue ?? "" },
                set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func field(_ title: String, _ value: Binding<String>,
                       hint: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            TextField(hint, text: value)
                .font(.system(size: 19))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 4)
    }

    private func multiline(_ title: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            TextEditor(text: value)
                .font(.system(size: 17, design: .monospaced))
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 4)
    }

    private func head(_ t: String) -> some View {
        Text(t).font(.system(size: 14, weight: .semibold)).tracking(1.6)
            .foregroundStyle(accent.opacity(0.75))
    }

    private func foot(_ t: String) -> some View {
        Text(t).font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
    }
}
