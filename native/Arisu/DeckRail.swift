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
    @AppStorage(Skin.freeFormKey) private var free = false
    @StateObject private var deck = Deck()
    @State private var editing = false
    @State private var group: String?
    /// How far a finger has the group wheel turned, in points.
    @State private var wheelDrag: CGFloat = 0
    /// The keys' horizontal pages and the order usage put the group in when it
    /// was last opened.
    @State private var page = 0
    @State private var keysDrag: CGFloat = 0
    @State private var ranking: [String: [String]] = [:]
    @State private var sheet: DeckButton?
    @State private var saveError: String?

    /// Three across, always: he lays the deck out in rows of three and the
    /// sleep key has to land bottom right (Oscar, 2026-09-30).
    private let three = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private let cyan = Skin.cyan
    private let mag = Skin.mag

    /// What it opens at the first time, as a share of the screen. He sets it
    /// after that by dragging the seam (Oscar, 2026-09-28): half the iPad is
    /// the deck he actually reaches for, and half is her.
    static let fraction = 0.5

    /// "Google Chrome" is Chrome on a rail this wide; "Citrix Workspace" is
    /// Citrix. The first word is the one he reads.
    private func short(_ app: String) -> String {
        let drop = ["Google ", "Microsoft ", "Apple "]
        var name = app
        for d in drop where name.hasPrefix(d) { name.removeFirst(d.count) }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// The group on show: his choice, or the first the Mac sent.
    private var shown: String { group ?? deck.groups.first ?? "" }

    /// Moving beyond this group's last page continues to the next app group.
    private func step(_ by: Int) {
        let all = deck.groups
        guard all.count > 1, let at = all.firstIndex(of: shown) else { return }
        group = all[(at + by + all.count) % all.count]
    }

    var body: some View {
        // Everything he presses sits at the bottom of the rail, where his hand
        // already is on a 13-inch iPad held in landscape (Oscar, 2026-09-28).
        // The title stays up top because he reads it and never touches it.
        VStack(alignment: .leading, spacing: 0) {
            head
            if let failed = deck.failed { note(failed) }
            else if deck.buttons.isEmpty && deck.loading {
                ProgressView().tint(cyan).padding(.bottom, 30).frame(maxWidth: .infinity)
            } else {
                // The colour on the button says done or failed; only a
                // failure with words left to say still prints them.
                if let said = deck.said, !said.ok, !said.detail.isEmpty { answer(said) }
                groups
                keys.padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The Record panel's look, so the two halves of the left side read as
        // one console (Oscar, 2026-09-30).
        .console(cyan, brackets: mag)
        .padding(10)
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
            Text("DECK//" + (shown.isEmpty ? "MAC" : shown.uppercased()))
                .font(Skin.mono(14, .bold)).tracking(2)
                .foregroundStyle(mag)
                .shadow(color: mag.opacity(0.9), radius: 6)
                .lineLimit(1)
            if !deck.frontApp.isEmpty {
                Text(deck.frontApp.uppercased())
                    .font(Skin.mono(10))
                    .foregroundStyle(cyan.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if editing {
                small("plus", "Add a button", tint: mag) {
                    sheet = DeckButton(id: freshID(), group: shown.isEmpty ? "Finder" : shown,
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

    /// The groups as a wheel (Oscar, 2026-10-01): the active one in the
    /// centre, its neighbours either side, dimmer the further out they sit,
    /// one text size throughout. It wraps. Dragging it rolls the labels under
    /// the finger and lets go onto the nearest; a tap on a neighbour rolls to it.
    private var groups: some View {
        let all = deck.groups
        let n = max(all.count, 1)
        let at = all.firstIndex(of: shown) ?? 0
        return GeometryReader { g in
            let slot = g.size.width / 5
            ZStack {
                ForEach(Array(all.enumerated()), id: \.offset) { i, name in
                    // Nearest way round. A label that wraps from one end to
                    // the other gets a new identity, so it fades rather than
                    // sliding back across the middle.
                    let o = { var o = ((i - at) % n + n) % n; if o > n / 2 { o -= n }; return o }()
                    let lap = (o - (i - at)) / n
                    let x = CGFloat(o) * slot + wheelDrag
                    let d = abs(x) / slot
                    // The name is the app: centred, a press brings it to the
                        // front on the Mac; off-centre, it turns the wheel to it
                        // (Oscar, 2026-10-01). The app buttons are gone.
                    Button {
                        if o == 0, deck.apps.contains(name) { Task { await deck.open(app: name) } }
                        else { roll(o) }
                    } label: {
                        Text("[\(short(name).uppercased())]")
                            .font(Skin.mono(13, .semibold))
                            .foregroundStyle(cyan.opacity(max(0, 1 - 0.3 * d)))
                            .shadow(color: d < 0.5 ? cyan : .clear, radius: 5)
                            .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(.plain)
                    .offset(x: x)
                    .opacity(d > 2.6 ? 0 : 1)
                    .id("\(name)#\(lap)")
                    .transition(.opacity)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { wheelDrag = $0.translation.width }
                    .onEnded { v in
                        roll(Int((-v.predictedEndTranslation.width / slot).rounded()))
                    }
            )
        }
        .frame(height: 32)
        .clipped()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Turn the wheel `by` places and let it settle.
    private func roll(_ by: Int) {
        let all = deck.groups
        guard !all.isEmpty, let at = all.firstIndex(of: shown) else { wheelDrag = 0; return }
        let next = ((at + by) % all.count + all.count) % all.count
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            wheelDrag = 0
            group = all[next]
        }
    }

    /// Eight actions per full-width page, always three rows. Larger groups scroll through
    /// full-width pages horizontally. The order is his usage, taken when the
    /// group comes up and then held, so keys stay put while he works.
    private static let perPage = 8
    /// Where the n-th most used key sits: bottom row first, where his hand is,
    /// then up.
    private static let seats = [6, 7, 3, 4, 5, 0, 1, 2]
    private static let permanentIDs: Set<String> = ["sleep", "mac.k3", "mac.close-active"]

    private var ordered: [DeckButton] {
        let mine = deck.buttons.filter { $0.group == shown && !Self.permanentIDs.contains($0.id) }
        guard !editing, let ids = ranking[shown] else { return mine }
        let byID = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] } + mine.filter { !ids.contains($0.id) }
    }

    private func rank() {
        let mine = deck.buttons.filter { $0.group == shown && !Self.permanentIDs.contains($0.id) }
        let saved = (UserDefaults.standard.dictionary(forKey: "arisu.deck.order") as? [String: [String]])?[shown]
        if let saved {
            let present = Set(mine.map(\.id))
            ranking[shown] = saved.filter { present.contains($0) }
                + mine.map(\.id).filter { !saved.contains($0) }
        } else {
            ranking[shown] = Usage.ranked(mine).map(\.id)
        }
        page = 0
    }

    private func actionPage(_ index: Int, width: CGFloat, buttons: [DeckButton]) -> some View {
        let slice = Array(buttons.dropFirst(index * Self.perPage).prefix(Self.perPage))
        var cells = [DeckButton?](repeating: nil, count: 9)
        for (position, button) in slice.enumerated() {
            cells[Self.seats[position]] = button
        }
        return LazyVGrid(columns: three, spacing: 10) {
            ForEach(0..<9, id: \.self) { cell in
                if let button = cells[cell] { key(button) }
                else { Color.clear.frame(minHeight: 50) }
            }
        }
        .frame(width: width)
        .id(index)
    }

    private var keys: some View {
        let all = ordered
        let pages = max(1, (all.count + Self.perPage - 1) / Self.perPage)
        let at = min(page, pages - 1)
        return VStack(spacing: 7) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(0..<pages, id: \.self) { index in
                        actionPage(index, width: geometry.size.width, buttons: all)
                    }
                }
                .offset(x: -CGFloat(at) * geometry.size.width + keysDrag)
                .frame(height: geometry.size.height, alignment: .top)
                .clipped()
            }
            if pages > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { i in
                        Circle().fill(i == at ? cyan : cyan.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .shadow(color: i == at ? cyan : .clear, radius: 4)
                    }
                }
            }
        }
        .frame(height: 183)
        .contentShape(Rectangle())
        .modifier(DeckPagingGesture(enabled: !editing, pages: pages,
                                    groups: deck.groups.count, at: at,
                                    drag: $keysDrag, page: $page, group: step))
    }

    /// A dragged key lands where the key it was dropped on was, in this
    /// group's own order on this iPad.
    private func moveKey(_ id: String, onto target: String) -> Bool {
        guard id != target,
              let from = ordered.firstIndex(where: { $0.id == id }),
              let to = ordered.firstIndex(where: { $0.id == target }) else { return false }
        var ids = ordered.map(\.id)
        let moved = ids.remove(at: from)
        ids.insert(moved, at: to)
        ranking[shown] = ids
        var orders = UserDefaults.standard.dictionary(forKey: "arisu.deck.order") as? [String: [String]] ?? [:]
        orders[shown] = ids
        UserDefaults.standard.set(orders, forKey: "arisu.deck.order")
        withAnimation { page = min(page, max(0, (ids.count - 1) / Self.perPage)) }
        return true
    }


    /// Cyan while nothing has happened, cyan-bright while it runs, green when
    /// it worked, red when it did not. The receipt that used to print under
    /// the rail is this colour now (Oscar, 2026-09-29) -- except for a failure
    /// with something to say, which still says it.
    private func outcomeInk(_ id: String, busy: Bool, editing: Bool) -> (Color, Double) {
        if editing { return (mag, 0.6) }
        if busy { return (cyan, 0.95) }
        switch deck.outcome[id] {
        case .some(true):  return (Skin.good, 0.95)
        case .some(false): return (Skin.recording, 0.95)
        case nil:          return (cyan, 0.5)
        }
    }

    private func key(_ b: DeckButton) -> some View {
        let busy = deck.running == b.id
        let symbol = b.action.symbol
        let ink = outcomeInk(b.id, busy: busy, editing: editing)
        return Button {
            if editing { sheet = b } else {
                Task { await deck.run(b) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(cyan)
                Text(b.label)
                    .font(Skin.mono(15, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // A thumb, not a stylus: 72pt is what he presses without looking.
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(alignment: .trailing) {
                if editing {
                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(mag)
                        .padding(.trailing, 10)
                }
            }
            .neon(ink.0, stroke: ink.1, fill: tintFill(deck.outcome[b.id]))
            .animation(.easeOut(duration: 0.2), value: deck.outcome[b.id])
        }
        .buttonStyle(.plain)
        // The sleep key stays where it is: bottom right, on every deck.
        .modifier(Held(about: b.about ?? b.action.summary,
                       id: b.id, movable: editing, move: moveKey))
    }

    /// A wash of the result colour inside the button, so it reads from across
    /// the desk and not only at arm's length.
    private func tintFill(_ outcome: Bool?) -> Color {
        switch outcome {
        case .some(true):  return Skin.good.opacity(0.14)
        case .some(false): return Skin.recording.opacity(0.16)
        case nil:          return cyan.opacity(0.06)
        }
    }

    /// What the Mac said about the last press. Kept on screen rather than
    /// flashed: half of these buttons answer with something worth reading, and
    /// the failures are the ones he needs the text of.
    private func answer(_ said: (id: String, ok: Bool, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(said.detail.isEmpty ? (said.ok ? "done" : "failed") : said.detail)
                .font(Skin.mono(11))
                .foregroundStyle(said.ok ? Skin.good : Skin.recording)
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

/// The four controls that never leave the screen, independent of which app's
/// actions are in the rail or which presentation mode is showing.
struct PermanentDeck: View {
    @StateObject private var deck = Deck()
    let eyeOn: Bool
    let toggleEye: () -> Void
    let sleep: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            action("mac.close-active", "Close", "xmark")
            action("mac.k3", "Screenshot", "camera")
            action("light", eyeOn ? "Light off" : "Light", eyeOn ? "eye.slash" : "eye",
                   invoke: toggleEye)
            action("sleep", "Sleep", "moon.zzz", invoke: {
                sleep()
                Task { _ = await deck.sleepMac() }
            })
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .top) { Rectangle().fill(Skin.cyan.opacity(0.45)).frame(height: 1) }
        .task { await deck.load() }
    }

    private func action(_ id: String, _ label: String, _ symbol: String,
                        invoke: (() -> Void)? = nil) -> some View {
        let busy = deck.running == id || (id == "sleep" && deck.running == "sleep")
        let ink: Color = busy ? Skin.cyan
            : deck.outcome[id].map { $0 ? Skin.good : Skin.recording } ?? Skin.cyan
        return Button {
            if let invoke { invoke() }
            else { Task { await deck.run(id: id) } }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(label).font(Skin.mono(13, .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color.black.opacity(0.4))
            .overlay(Rectangle().stroke(ink.opacity(busy ? 0.95 : 0.55), lineWidth: 1))
            .shadow(color: ink.opacity(busy ? 0.65 : 0.18), radius: busy ? 6 : 2)
            .animation(.easeOut(duration: 0.2), value: deck.outcome[id])
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Long press says what the button does; press and drag moves it onto
/// another's place (Oscar, 2026-09-30). The context menu and the drag are the
/// system's own pair: hold to read it, keep moving to carry it. A nil id is a
/// button that explains itself but stays put.
/// A sideways swipe across the keys turns their page; past the last page (or
/// before the first) it moves on to the next application's deck.
struct DeckPagingGesture: ViewModifier {
    let enabled: Bool
    let pages: Int
    let groups: Int
    let at: Int
    @Binding var drag: CGFloat
    @Binding var page: Int
    let group: (Int) -> Void

    private func sideways(_ v: DragGesture.Value) -> Bool {
        enabled && (pages > 1 || groups > 1)
            && abs(v.translation.width) > abs(v.translation.height)
    }

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in if sideways(v) { drag = v.translation.width } }
                .onEnded { v in
                    guard sideways(v) else { drag = 0; return }
                    let by = v.predictedEndTranslation.width < -50 ? 1
                           : v.predictedEndTranslation.width > 50 ? -1 : 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if by > 0, at + 1 < pages { page = at + 1 }
                        else if by < 0, at > 0 { page = at - 1 }
                        else if by != 0 { group(by) }
                        drag = 0
                    }
                }
        )
    }
}

struct Held: ViewModifier {
    let about: String
    let id: String?
    var movable = false
    let move: (String, String) -> Bool

    func body(content: Content) -> some View {
        if let id, movable {
            content
                .contextMenu { Text(about) }
                .draggable(id)
                .dropDestination(for: String.self) { got, _ in
                    got.first.map { move($0, id) } ?? false
                }
        } else {
            content.contextMenu { Text(about) }
        }
    }
}

extension View {
    /// The Record panel's box: square, a thin neon edge, a glow once it has
    /// something to say (lit, done or failed).
    func neon(_ tint: Color, stroke: Double, fill: Color) -> some View {
        plate { Rectangle().fill(fill) }
            .edge { Rectangle().stroke(tint.opacity(stroke), lineWidth: 1) }
            .shadow(color: stroke > 0.9 || stroke == 0 ? tint.opacity(0.7) : .clear, radius: 5)
    }
}
