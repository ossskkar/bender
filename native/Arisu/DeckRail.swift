import SwiftUI

/// The deck, as a column down the right-hand side of whichever screen he is on.
///
/// It was a full screen he opened and closed (`DeckScreen`) until 2026-09-27.
/// Two things were wrong with that: pressing a Mac button meant leaving the
/// conversation, and the deck he reaches for most while talking to her was the
/// one thing the app hid. It is a rail now, up in both modes, and one group at
/// a time -- six buttons fit two across with nothing to scroll, which is what
/// makes a column this narrow worth more than a grid he has to open.
///
/// A tap presses; the pencil turns the rail into something he can edit. Nothing
/// is executed here -- the iPad sends an id and the Mac decides what that id
/// means (see `Deck`).
struct DeckRail: View {
    @StateObject private var deck = Deck()
    @State private var editing = false
    @State private var group: String?
    @State private var sheet: DeckButton?
    @State private var saveError: String?

    private let cyan = Color(red: 0.27, green: 0.90, blue: 0.97)
    private let mag = Color(red: 1.0, green: 0.22, blue: 0.78)

    /// Wide enough for two keys and a group chip row, narrow enough to leave
    /// her the middle of a landscape iPad.
    static let width: CGFloat = 196

    /// The group on show: his choice, or the first the Mac sent.
    private var shown: String { group ?? deck.groups.first ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            if let failed = deck.failed { note(failed) }
            else if deck.buttons.isEmpty && deck.loading {
                ProgressView().tint(cyan).padding(.top, 30).frame(maxWidth: .infinity)
            } else {
                groups
                keys
            }
            Spacer(minLength: 0)
            if let said = deck.said { answer(said) }
        }
        .frame(width: Self.width)
        .background(cyan.opacity(0.03))
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

    /// The masthead's height, so the rail's own title sits on the same line as
    /// her name and the buttons across the top.
    private var head: some View {
        HStack(spacing: 6) {
            Text("DECK")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(mag.opacity(0.85))
            Spacer(minLength: 0)
            if editing {
                small("plus", "Add a button", tint: mag) {
                    sheet = DeckButton(id: freshID(), group: shown.isEmpty ? "mac" : shown,
                                       label: "New button")
                }
            }
            small(editing ? "pencil.circle.fill" : "pencil", "Edit",
                  tint: editing ? mag : cyan.opacity(0.7)) { editing.toggle() }
            small("arrow.clockwise", "Reload", tint: cyan.opacity(0.7)) {
                Task { await deck.load() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
        .padding(.bottom, 10)
    }

    private var groups: some View {
        // A row that wraps: six short names do not fit across 196pt, and a
        // horizontal scroller hides half of them behind a gesture.
        FlowRow(spacing: 5) {
            ForEach(deck.groups, id: \.self) { name in
                let on = name == shown
                Button { group = name } label: {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(on ? Color(red: 0.02, green: 0.09, blue: 0.10) : cyan.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(on ? cyan : .clear))
                        .overlay(Capsule().stroke(cyan.opacity(on ? 0 : 0.3)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var keys: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                  spacing: 8) {
            ForEach(deck.buttons.filter { $0.group == shown }) { key($0) }
        }
        .padding(.horizontal, 12)
    }

    private func key(_ b: DeckButton) -> some View {
        let busy = deck.running == b.id
        return Button {
            if editing { sheet = b } else { Task { await deck.run(b) } }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if !b.icon.isEmpty { Text(b.icon).font(.system(size: 14)) }
                    Text(b.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if busy { ProgressView().tint(cyan).scaleEffect(0.55) }
                    else if editing {
                        Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(mag)
                    }
                }
                Text(b.action.summary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(cyan.opacity(0.55))
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke((editing ? mag : cyan).opacity(busy ? 0.9 : 0.3)))
        }
        .buttonStyle(.plain)
    }

    /// What the Mac said about the last press. Kept on screen rather than
    /// flashed: half of these buttons answer with something worth reading, and
    /// the failures are the ones he needs the text of.
    private func answer(_ said: (id: String, ok: Bool, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: said.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(said.ok ? cyan : mag)
            Text(said.detail.isEmpty ? (said.ok ? "done" : "failed") : said.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(5)
            Spacer(minLength: 0)
            Button { deck.said = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(cyan.opacity(0.2)),
                 alignment: .top)
    }

    private func note(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            Button("Try again") { Task { await deck.load() } }
                .font(.system(size: 13, weight: .semibold)).tint(cyan)
        }
        .padding(.horizontal, 12)
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

    private func small(_ symbol: String, _ label: String, tint: Color,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A row that wraps, which SwiftUI has no stack for. Only the group chips use
/// it, so it does the one thing they need: lay out in order, break on width.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += line + spacing; line = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
