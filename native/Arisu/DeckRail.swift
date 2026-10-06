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
    /// The keys' wheel: which page of eight is up, how far a finger has it
    /// turned, and the order usage put the group in when it was last opened.
    @State private var page = 0
    @State private var keysDrag: CGFloat = 0
    @State private var ranking: [String: [String]] = [:]
    @State private var sheet: DeckButton?
    @State private var saveError: String?
    /// Blacked out by the sleep key, with the brightness to go back to.
    @State private var asleep = false
    @State private var wasBright: CGFloat = 0.5
    @Environment(\.scenePhase) private var phase

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

    /// One deck along, wrapping at both ends -- a swipe that does nothing at
    /// the last group reads as a dropped gesture, not as an edge.
    private func step(_ by: Int) {
        let all = deck.groups
        guard all.count > 1, let at = all.firstIndex(of: shown) else { return }
        let next = (at + by + all.count) % all.count
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { group = all[next] }
    }

    /// The group on show: his choice, or the first the Mac sent.
    private var shown: String { group ?? deck.groups.first ?? "" }

    var body: some View {
        // Everything he presses sits at the bottom of the rail, where his hand
        // already is on a 13-inch iPad held in landscape (Oscar, 2026-09-28).
        // The title stays up top because he reads it and never touches it.
        VStack(alignment: .leading, spacing: 0) {
            head
            // The room above the keys, which was empty (Oscar keeps the keys at
            // the bottom, three rows, a quarter of the screen): what his
            // builder agents are doing, so he can follow them from the iPad
            // without opening lain's Agents page (18.0).
            AgentBoard()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tourSpot("agents")
            if let failed = deck.failed { note(failed) }
            else if deck.buttons.isEmpty && deck.loading {
                ProgressView().tint(cyan).padding(.bottom, 30).frame(maxWidth: .infinity)
            } else {
                // The colour on the button says done or failed; only a
                // failure with words left to say still prints them.
                if let said = deck.said, !said.ok, !said.detail.isEmpty { answer(said) }
                groups
                keys.padding(.bottom, 10)
                fixedRow.padding(.bottom, 14)
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
        // The Record panel's look, so the two halves of the left side read as
        // one console (Oscar, 2026-09-30).
        .console(cyan, brackets: mag)
        .padding(10)
        .task { await deck.load() }
        .task { await deck.watchFront() }
        .task { await deck.readLight() }
        // The Mac changed app: bring that deck up. Only on the change, never
        // continuously -- a rail that re-asserts itself every two seconds is
        // one he cannot hold on a different group while he works.
        .onChange(of: deck.front) { _, now in
            guard !now.isEmpty, deck.groups.contains(now) else { return }
            withAnimation(.easeOut(duration: 0.18)) { group = now }
        }
        .fullScreenCover(isPresented: $asleep) {
            Color.black.ignoresSafeArea().onTapGesture { wake() }
        }
        .onChange(of: phase) { _, now in if now == .active { wake() } }
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

    /// Eight actions and sleep, always three rows (Oscar, 2026-10-01). A group
    /// with more than eight is a wheel of pages: drag up or down to turn it.
    /// The order is his usage, taken when the group comes up and then held, so
    /// a key never moves out from under a finger that is about to press it.
    private static let perPage = 8
    /// Where the n-th most used key sits: bottom row first, where his hand is,
    /// then up. Cell 8 -- bottom right -- is sleep's.
    private static let seats = [6, 7, 3, 4, 5, 0, 1, 2]

    private var ordered: [DeckButton] {
        let mine = deck.buttons.filter { $0.group == shown && $0.id != DeckButton.sleepID }
        guard !editing, let ids = ranking[shown] else { return mine }
        let byID = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] } + mine.filter { !ids.contains($0.id) }
    }

    private func rank() {
        let mine = deck.buttons.filter { $0.group == shown && $0.id != DeckButton.sleepID }
        ranking[shown] = Usage.ranked(mine).map(\.id)
        page = 0
    }

    private var keys: some View {
        let all = ordered
        let pages = max(1, (all.count + Self.perPage - 1) / Self.perPage)
        let at = min(page, pages - 1)
        let slice = Array(all.dropFirst(at * Self.perPage).prefix(Self.perPage))
        var cells = [DeckButton?](repeating: nil, count: 9)
        for (j, b) in slice.enumerated() { cells[Self.seats[j]] = b }
        let turn = Double(keysDrag) / 160
        return HStack(spacing: 6) {
            LazyVGrid(columns: three, spacing: 10) {
                ForEach(0..<9, id: \.self) { i in
                    if let b = cells[i] { key(b) } else { Color.clear.frame(minHeight: 50) }
                }
            }
            .id(at)
            .transition(.asymmetric(
                insertion: .move(edge: keysDrag <= 0 ? .bottom : .top).combined(with: .opacity),
                removal: .opacity))
            .rotation3DEffect(.degrees(-turn * 40), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .offset(y: keysDrag * 0.25)
            .opacity(1 - min(0.5, abs(turn) * 0.5))
            if pages > 1 {
                VStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { i in
                        Circle().fill(i == at ? cyan : cyan.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .shadow(color: i == at ? cyan : .clear, radius: 4)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in
                    guard pages > 1, abs(v.translation.height) > abs(v.translation.width) else { return }
                    keysDrag = v.translation.height
                }
                .onEnded { v in
                    guard pages > 1, abs(v.translation.height) > abs(v.translation.width) else {
                        keysDrag = 0; return
                    }
                    let by = v.predictedEndTranslation.height < -50 ? 1
                           : v.predictedEndTranslation.height > 50 ? -1 : 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        page = ((at + by) % pages + pages) % pages
                        keysDrag = 0
                    }
                }
        )
        .onAppear(perform: rank)
        .onChange(of: shown) { _, _ in rank() }
        .onChange(of: deck.buttons.count) { _, _ in rank() }
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
        let symbol = b.id == DeckButton.sleepID ? "moon.zzz" : b.action.symbol
        let ink = outcomeInk(b.id, busy: busy, editing: editing)
        return Button {
            if editing { sheet = b } else {
                Task { await deck.run(b) }
                if b.id == DeckButton.sleepID { goSleep() }
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
            // The result mark sits in the corner so the label stays centred.
            .overlay(alignment: .trailing) {
                Group {
                    if busy { ProgressView().tint(cyan).scaleEffect(0.55) }
                    else if editing {
                        Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(mag)
                    } else if let ok = deck.outcome[b.id] {
                        Image(systemName: ok ? "checkmark" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ok ? Skin.good : Skin.recording)
                    }
                }
                .padding(.trailing, 10)
            }
            .neon(ink.0, stroke: ink.1, fill: tintFill(deck.outcome[b.id]))
            .animation(.easeOut(duration: 0.2), value: deck.outcome[b.id])
        }
        .buttonStyle(.plain)
        // The sleep key stays where it is: bottom right, on every deck.
        .modifier(Held(about: b.about ?? b.action.summary,
                       id: b.id == DeckButton.sleepID ? nil : b.id, move: moveKey))
    }

    /// A dragged key lands where the key it was dropped on was.
    private func moveKey(_ id: String, onto target: String) -> Bool {
        guard id != target,
              let from = deck.buttons.firstIndex(where: { $0.id == id }),
              let to = deck.buttons.firstIndex(where: { $0.id == target }) else { return false }
        withAnimation { deck.buttons.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to) }
        Task { saveError = await deck.save() }
        return true
    }

    /// The same four on every group, under the keys (Oscar, 2026-10-06):
    /// close the Mac's front app, screenshot, God's Eye on/off, sleep.
    private var fixedRow: some View {
        HStack(spacing: 8) {
            fixed("mac.close-active", "Close", "xmark") { Task { await deck.run(id: "mac.close-active") } }
            fixed("mac.k3", "Screenshot", "camera") { Task { await deck.run(id: "mac.k3") } }
            fixed("light", deck.lightOn == true ? "Light off" : "Light",
                  deck.lightOn == true ? "lightbulb.slash" : "lightbulb") { Task { await deck.toggleLight() } }
            fixed("sleep", "Sleep", "moon.zzz") {
                goSleep()
                Task { _ = await deck.sleepMac() }
            }
        }
    }

    private func fixed(_ id: String, _ label: String, _ symbol: String,
                       press: @escaping () -> Void) -> some View {
        let busy = deck.running == id
        let ink: Color = busy ? cyan : deck.outcome[id].map { $0 ? Skin.good : Skin.recording } ?? cyan
        return Button(action: press) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(label).font(Skin.mono(13, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .neon(ink, stroke: busy ? 0.95 : 0.5, fill: tintFill(deck.outcome[id]))
            .animation(.easeOut(duration: 0.2), value: deck.outcome[id])
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// iPadOS will not let an app lock the iPad, so this is the nearest: the
    /// screen goes to zero and black, and the wake lock is let go so the
    /// iPad's own Auto-Lock takes it from there. A tap brings it back.
    private func goSleep() {
        wasBright = UIScreen.main.brightness
        UIScreen.main.brightness = 0
        UIApplication.shared.isIdleTimerDisabled = false
        asleep = true
    }

    private func wake() {
        guard asleep else { return }
        UIScreen.main.brightness = wasBright
        UIApplication.shared.isIdleTimerDisabled = true
        asleep = false
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

/// Long press says what the button does; press and drag moves it onto
/// another's place (Oscar, 2026-09-30). The context menu and the drag are the
/// system's own pair: hold to read it, keep moving to carry it. A nil id is a
/// button that explains itself but stays put.
struct Held: ViewModifier {
    let about: String
    let id: String?
    let move: (String, String) -> Bool

    func body(content: Content) -> some View {
        if let id {
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

// MARK: - Agents

/// One builder agent as lain's Agents page has it (`GET /agents`, written by
/// `~/.claude/agent-loops/report.py`). The iPad only reads.
struct AgentRun: Identifiable, Equatable {
    let id: String
    let state: String
    let doing: String
    let updated: Date
    /// When the run in progress began; nil once it is over.
    let since: Date?
}

@MainActor final class Agents: ObservableObject {
    @Published private(set) var runs: [AgentRun] = []
    static let url = URL(string: "https://architect-server.tailaa64e9.ts.net:8443/agents")!

    /// Every 30 s while the rail is up: a milestone comes every few minutes,
    /// so faster only repeats the same answer. A failed fetch keeps what was
    /// showing; a published list only when it changed.
    func watch() async {
        while !Task.isCancelled {
            if let (data, _) = try? await URLSession.shared.data(from: Self.url),
               let got = Self.parse(data), got != runs {
                runs = got
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// Working first, then the most recent.
    static func parse(_ data: Data) -> [AgentRun]? {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let all = top["agents"] as? [String: [String: Any]] else { return nil }
        func date(_ v: Any?) -> Date? { (v as? Double).map { Date(timeIntervalSince1970: $0) } }
        return all.map { name, a in
            AgentRun(id: name, state: a["state"] as? String ?? "", doing: a["doing"] as? String ?? "",
                     updated: date(a["updated"]) ?? .distantPast,
                     since: (a["state"] as? String) == "working" || (a["state"] as? String) == "started"
                         ? date(a["since"]) : nil)
        }
        .sorted { ($0.busy ? 0 : 1, -$0.updated.timeIntervalSince1970)
                < ($1.busy ? 0 : 1, -$1.updated.timeIntervalSince1970) }
    }
}

extension AgentRun {
    var busy: Bool { state == "working" || state == "started" }
}

/// The rail's empty middle, put to work: one line per agent -- its name, what
/// it is doing in its own words, and how long ago. Tapping the title opens
/// lain's Agents page. Fewer lines when the room is short, nothing when there
/// is none, so the keys never move.
struct AgentBoard: View {
    @StateObject private var agents = Agents()
    private let page = URL(string: "https://architect-server.tailaa64e9.ts.net:8443/systems/agents.html")!

    var body: some View {
        // ViewThatFits picks the first that fits the height: two lines of
        // detail each, one line each, the title alone, then nothing.
        ViewThatFits(in: .vertical) {
            board(lines: 2)
            board(lines: 1)
            title
            Color.clear.frame(height: 0)
        }
        .padding(.horizontal, 12)
        .task { await agents.watch() }
    }

    private var title: some View {
        Link(destination: page) {
            HStack(spacing: 6) {
                Text("AGENTS").font(Skin.mono(12, .bold)).tracking(2).foregroundStyle(Skin.mag)
                let busy = agents.runs.filter(\.busy).count
                Text(busy == 0 ? "ALL QUIET" : "\(busy) AT WORK")
                    .font(Skin.mono(11)).foregroundStyle(Skin.cyan.opacity(0.7))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(Skin.cyan.opacity(0.5))
            }
        }
    }

    @ViewBuilder private func board(lines: Int) -> some View {
        if agents.runs.isEmpty { title } else {
            // The ages move on by themselves; the list only when lain says so.
            TimelineView(.everyMinute) { tl in
                VStack(alignment: .leading, spacing: 10) {
                    title
                    ForEach(agents.runs) { run in row(run, lines: lines, now: tl.date) }
                }
            }
        }
    }

    private func row(_ run: AgentRun, lines: Int, now: Date) -> some View {
        let ink: Color = run.busy ? Skin.cyan
            : run.state == "failed" ? Skin.recording
            : run.state == "done" ? Skin.good : Skin.cyan.opacity(0.45)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(ink).frame(width: 6, height: 6)
                .shadow(color: run.busy ? ink : .clear, radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.id.uppercased()).font(Skin.mono(13, .semibold)).foregroundStyle(.white)
                    Text(run.state.uppercased()).font(Skin.mono(10)).foregroundStyle(ink)
                    Spacer(minLength: 0)
                    Text(Self.ago(run.since ?? run.updated, now: now, running: run.busy))
                        .font(Skin.mono(10)).foregroundStyle(Skin.cyan.opacity(0.55))
                }
                Text(run.doing).font(Skin.mono(12)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(lines).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "FOR 12 MIN" while it works (since it started), "3 H AGO" after.
    static func ago(_ t: Date, now: Date, running: Bool) -> String {
        let m = max(0, Int(now.timeIntervalSince(t) / 60))
        let span = m < 1 ? "<1 MIN" : m < 60 ? "\(m) MIN" : m < 48 * 60 ? "\(m / 60) H" : "\(m / 1440) D"
        return running ? "FOR " + span : span + " AGO"
    }
}

