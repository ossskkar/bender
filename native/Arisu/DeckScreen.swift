import SwiftUI

/// The deck on screen: his Mac's buttons in a grid, grouped as the pad's pads
/// were. A tap presses; the pencil turns the grid into something he can edit.
///
/// It deliberately looks like the rest of the app rather than like a Form:
/// this is the hologram's other screen, and he reaches for it from across the
/// desk, so the targets are large and the whole thing is one page.
struct DeckScreen: View {
    let close: () -> Void
    @StateObject private var deck = Deck()
    @State private var editing = false
    @State private var sheet: DeckButton?
    @State private var saveError: String?

    private let cyan = Color(red: 0.27, green: 0.90, blue: 0.97)
    private let mag = Color(red: 1.0, green: 0.22, blue: 0.78)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                top
                if let failed = deck.failed { note(failed) }
                else if deck.buttons.isEmpty && deck.loading { ProgressView().tint(cyan).padding(40) }
                else { grid }
                Spacer(minLength: 0)
                if let said = deck.said { answer(said) }
            }
        }
        .preferredColorScheme(.dark)
        .task { await deck.load() }
        .sheet(item: $sheet) { button in
            DeckEditor(button: button, isNew: !deck.buttons.contains { $0.id == button.id },
                       groups: deck.groups) { edited in
                apply(edited)
            } remove: {
                deck.buttons.removeAll { $0.id == button.id }
                Task { saveError = await deck.save() }
            }
        }
        .alert("The Mac refused that", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var top: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DECK")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(cyan)
                Text("his Mac, from here")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(cyan.opacity(0.45))
            }
            Spacer(minLength: 12)
            square(editing ? "pencil.circle.fill" : "pencil", "Edit",
                   tint: editing ? mag : cyan) { editing.toggle() }
            if editing {
                square("plus", "Add a button") {
                    sheet = DeckButton(id: freshID(), group: deck.groups.first ?? "mac",
                                       label: "New button")
                }
            }
            square("arrow.clockwise", "Reload") { Task { await deck.load() } }
            square("xmark", "Close") { close() }
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(deck.groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.uppercased())
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(mag.opacity(0.85))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                                 count: 3), spacing: 12) {
                            ForEach(deck.buttons.filter { $0.group == group }) { key($0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
        }
    }

    private func key(_ b: DeckButton) -> some View {
        let busy = deck.running == b.id
        return Button {
            if editing { sheet = b } else { Task { await deck.run(b) } }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if !b.icon.isEmpty { Text(b.icon).font(.system(size: 20)) }
                    Text(b.label)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if busy { ProgressView().tint(cyan).scaleEffect(0.7) }
                    else if editing {
                        Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(mag)
                    }
                }
                Text(b.action.summary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(cyan.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke((editing ? mag : cyan).opacity(busy ? 0.9 : 0.3)))
        }
        .buttonStyle(.plain)
    }

    /// What the Mac said about the last press. Kept on screen rather than
    /// flashed: half of these buttons answer with something worth reading, and
    /// the failures are the ones he needs the text of.
    private func answer(_ said: (id: String, ok: Bool, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: said.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(said.ok ? cyan : mag)
            Text(said.detail.isEmpty ? (said.ok ? "done" : "failed") : said.detail)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(6)
            Spacer(minLength: 0)
            Button { deck.said = nil } label: {
                Image(systemName: "xmark").foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(cyan.opacity(0.2)),
                 alignment: .top)
    }

    private func note(_ line: String) -> some View {
        VStack(spacing: 14) {
            Text(line).multilineTextAlignment(.center)
                .font(.system(size: 17)).foregroundStyle(.white.opacity(0.7))
            Button("Try again") { Task { await deck.load() } }
                .font(.system(size: 18, weight: .semibold)).tint(cyan)
        }
        .padding(40)
    }

    private func apply(_ edited: DeckButton) {
        if let i = deck.buttons.firstIndex(where: { $0.id == edited.id }) {
            deck.buttons[i] = edited
        } else {
            deck.buttons.append(edited)
        }
        Task { saveError = await deck.save() }
    }

    /// Ids are the Mac's key for a button, so a new one has to be unique and
    /// stay readable in buttons.json.
    private func freshID() -> String {
        var n = deck.buttons.count + 1
        while deck.buttons.contains(where: { $0.id == "new.k\(n)" }) { n += 1 }
        return "new.k\(n)"
    }

    private func square(_ symbol: String, _ label: String, tint: Color? = nil,
                        action: @escaping () -> Void) -> some View {
        let ink = tint ?? cyan
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 50, height: 38)
                .background(Color.black.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
    }
}
