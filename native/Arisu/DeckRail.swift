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

    private let cyan = Skin.cyan
    private let mag = Skin.mag

    /// What it opens at the first time, as a share of the screen. He sets it
    /// after that by dragging the seam (Oscar, 2026-09-28): half the iPad is
    /// the deck he actually reaches for, and half is her.
    static let fraction = 0.5

    /// His applications, above the tabs: they are what *chooses* a tab, so
    /// they read top-down -- application, then its deck, then its keys, with
    /// the keys lowest because those are pressed most (Oscar, 2026-09-28).
    /// Pressing one moves the Mac, and the rail follows the Mac, so the right
    /// deck arrives on its own a moment later.
    private var appStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Skin.caption("apps", Skin.ink)
                .padding(.horizontal, 12)
            // The same button as a key, in the same grid: an application is
            // something he presses, and two sizes of press on one rail made
            // the smaller one look like a label (Oscar, 2026-09-29).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                ForEach(deck.apps, id: \.self) { app in
                    let here = app.lowercased() == deck.frontApp.lowercased()
                    Button { Task { await deck.open(app: app) } } label: {
                        HStack(spacing: 8) {
                            // The application's own icon, from the Mac
                            // (GET /deck/icon). A window glyph said nothing
                            // about which app it was (Oscar, 2026-09-29).
                            AsyncImage(url: DeckAPI.base
                                .appendingPathComponent("deck/icon")
                                .appending(queryItems: [URLQueryItem(name: "name", value: app)])) {
                                    $0.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Skin.cyan.opacity(0.5))
                                }
                                .frame(width: 26, height: 26)
                            Text(short(app))
                                .font(Skin.mono(15, .semibold))
                                .foregroundStyle(here ? Skin.onLit : .white)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .raised(deck.outcome[app] == false ? Skin.recording : Skin.cyan,
                                stroke: here ? 0 : (deck.outcome[app] == nil ? 0.3 : 0.95),
                                fill: here ? Skin.cyan : tintFill(deck.outcome[app]))
                        .animation(.easeOut(duration: 0.2), value: deck.outcome[app])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    /// "Google Chrome" is Chrome on a rail this wide; "Citrix Workspace" is
    /// Citrix. The first word is the one he reads.
    private func short(_ app: String) -> String {
        let drop = ["Google ", "Microsoft ", "Apple "]
        var name = app
        for d in drop where name.hasPrefix(d) { name.removeFirst(d.count) }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// One deck along, wrapping at both ends -- a swipe that does nothing at
    /// the last group reads as a dropped gesture, not as an edge.
    private func step(_ by: Int) {
        let all = deck.groups
        guard all.count > 1, let at = all.firstIndex(of: shown) else { return }
        let next = (at + by + all.count) % all.count
        withAnimation(.easeOut(duration: 0.18)) { group = all[next] }
    }

    /// The group on show: his choice, or the first the Mac sent.
    private var shown: String { group ?? deck.groups.first ?? "" }

    var body: some View {
        // Everything he presses sits at the bottom of the rail, where his hand
        // already is on a 13-inch iPad held in landscape (Oscar, 2026-09-28).
        // The title stays up top because he reads it and never touches it.
        VStack(alignment: .leading, spacing: 0) {
            head
            Spacer(minLength: 0)
            if let failed = deck.failed { note(failed) }
            else if deck.buttons.isEmpty && deck.loading {
                ProgressView().tint(cyan).padding(.bottom, 30).frame(maxWidth: .infinity)
            } else {
                // The colour on the button says done or failed; only a
                // failure with words left to say still prints them.
                if let said = deck.said, !said.ok, !said.detail.isEmpty { answer(said) }
                appStrip.padding(.bottom, 14)
                groups
                keys.padding(.bottom, 18)
            }
        }
        // A swipe across the keys is the next application's deck. Six chips
        // are a fine target with a stylus and a poor one with a thumb, and
        // switching deck is the thing he does most often after pressing one.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { move in
                    guard abs(move.translation.width) > abs(move.translation.height) else { return }
                    step(move.translation.width < 0 ? 1 : -1)
                }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .task { await deck.load() }
        .task { await deck.watchFront() }
        // The Mac changed app: bring that deck up. Only on the change, never
        // continuously -- a rail that re-asserts itself every two seconds is
        // one he cannot hold on a different group while he works.
        .onChange(of: deck.front) { _, now in
            guard !now.isEmpty, deck.groups.contains(now) else { return }
            withAnimation(.easeOut(duration: 0.18)) { group = now }
        }
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

    /// The rail's own label. Her name is the app's title and lives in the row
    /// above this one now, so this is only "which panel is this".
    private var head: some View {
        HStack(spacing: 6) {
            Skin.caption("deck", mag.opacity(0.85))
            if !deck.frontApp.isEmpty {
                Text(deck.frontApp)
                    .font(Skin.mono(10))
                    .foregroundStyle(Skin.ink)
                    .lineLimit(1)
            }
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
        .padding(.top, 14)
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
                        .font(Skin.mono(13, .semibold))
                        .foregroundStyle(on ? Skin.onLit : cyan.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(on ? cyan : .clear))
                        .overlay(Capsule().stroke(cyan.opacity(on ? 0 : 0.3)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var keys: some View {
        // As many columns as the seam leaves room for. It was two across a
        // fixed 196pt rail; the rail is his to widen now, and a two-column
        // grid on half an iPad is six buttons swimming in black.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            ForEach(deck.buttons.filter { $0.group == shown }) { key($0) }
        }
        .padding(.horizontal, 12)
    }

    /// Cyan while nothing has happened, cyan-bright while it runs, green when
    /// it worked, red when it did not. The receipt that used to print under
    /// the rail is this colour now (Oscar, 2026-09-29) -- except for a failure
    /// with something to say, which still says it.
    private func outcomeInk(_ id: String, busy: Bool, editing: Bool) -> (Color, Double) {
        if editing { return (mag, 0.3) }
        if busy { return (cyan, 0.95) }
        switch deck.outcome[id] {
        case .some(true):  return (Skin.good, 0.95)
        case .some(false): return (Skin.recording, 0.95)
        case nil:          return (cyan, 0.3)
        }
    }

    private func key(_ b: DeckButton) -> some View {
        let busy = deck.running == b.id
        let ink = outcomeInk(b.id, busy: busy, editing: editing)
        return Button {
            if editing { sheet = b } else { Task { await deck.run(b) } }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if !b.icon.isEmpty { Text(b.icon).font(.system(size: 20)) }
                    Text(b.label)
                        .font(Skin.mono(15, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if busy { ProgressView().tint(cyan).scaleEffect(0.55) }
                    else if editing {
                        Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(mag)
                    } else if let ok = deck.outcome[b.id] {
                        Image(systemName: ok ? "checkmark" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ok ? Skin.good : Skin.recording)
                    }
                }
                Text(b.action.summary)
                    .font(Skin.mono(10))
                    .foregroundStyle(Skin.ink)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            // A thumb, not a stylus: 72pt is what he presses without looking.
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .raised(ink.0, stroke: ink.1,
                    fill: tintFill(deck.outcome[b.id]))
            .animation(.easeOut(duration: 0.2), value: deck.outcome[b.id])
        }
        .buttonStyle(.plain)
    }

    /// A wash of the result colour inside the button, so it reads from across
    /// the desk and not only at arm's length.
    private func tintFill(_ outcome: Bool?) -> Color {
        switch outcome {
        case .some(true):  return Skin.good.opacity(0.14)
        case .some(false): return Skin.recording.opacity(0.16)
        case nil:          return Skin.raised
        }
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
                .font(Skin.mono(11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(5)
            Spacer(minLength: 0)
            Button { deck.said = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(12)
        .raised(cyan, stroke: 0.25)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
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
