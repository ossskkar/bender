import SwiftUI

/// The typed conversation, drawn by the app.
///
/// It was `chat.html` in a web view until 2026-09-28 -- the same page Safari
/// shows on his work phones, embedded with `?chrome=0` so it drew no second
/// masthead. That page is still the phones' chat; this is the iPad's, and it
/// is native so the composer can hand the screen to her voice without a
/// bridge, and so the thread scrolls at the frame rate of everything else.
///
/// The desk owns the conversation. `GET /arisu/chat` is what is on the thread
/// now, `POST /arisu/chat` takes one line and answers it, and the id of the
/// session is the desk's business, not this screen's.
@MainActor final class Chat: ObservableObject {
    struct Line: Identifiable, Equatable {
        let id = UUID()
        let mine: Bool
        var text: String
        let at: Date
        /// Spoken, and merged back into the typed thread afterwards. Drawn
        /// dimmer, with a microphone, because a line he said out loud two
        /// hours ago should not read like one he typed just now.
        var spoken = false
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var thinking = false
    @Published var failed: String?
    /// Conversations, newest first, for the history sheet.
    @Published private(set) var sessions: [Session] = []
    /// What he is likely to type next, from the desk (Oscar, 2026-10-02):
    /// four answers to her last line, most likely first, and commands made
    /// for the moment. lain's server/suggest.py makes them, one cached Gemini
    /// call shared with the web chat, so asking often costs nothing extra.
    @Published private(set) var suggestions = Suggestions()

    struct Suggestions: Decodable, Equatable {
        struct Command: Decodable, Equatable, Hashable { let label: String; let text: String }
        var replies: [String] = []
        var commands: [Command] = []
        var isEmpty: Bool { replies.isEmpty && commands.isEmpty }
    }

    struct Session: Identifiable, Decodable {
        let id: String
        let kind: String
        let start: Double
        let end: Double
        let count: Int
        let preview: String
    }

    private struct Thread: Decodable {
        struct Message: Decodable {
            let who: String
            let text: String
            let t: Double?
            let via: String?
        }
        // `session` is an object on the wire; decoding it as a string failed
        // the whole thread, so no old conversation would open (2026-09-30).
        let messages: [Message]
    }

    private struct Answer: Decodable { let answer: String?; let error: String? }
    private struct Sessions: Decodable { let sessions: [Session] }

    private let net: URLSession = {
        let c = URLSessionConfiguration.default
        // One typed turn is a whole Hermes turn on architect, same as her
        // voice: seconds warm, much worse on a quota failover.
        c.timeoutIntervalForRequest = 120
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    private static func line(_ m: Thread.Message) -> Line {
        Line(mine: m.who == "you", text: m.text,
             at: Date(timeIntervalSince1970: (m.t ?? 0) / 1000),
             spoken: (m.via ?? "") == "voice")
    }

    /// What is on the thread now.
    func load() async {
        do {
            let (data, _) = try await net.data(from: Brain.base.appendingPathComponent("chat"))
            lines = Self.once(try JSONDecoder().decode(Thread.self, from: data).messages.map(Self.line))
            failed = nil
        } catch {
            failed = "could not reach the desk"
        }
    }

    /// Say one thing and wait for her answer. His line lands immediately --
    /// the wait is hers, and a composer that clears only once the desk has
    /// answered feels broken at seven seconds a turn.
    func send(_ text: String) async {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !thinking else { return }
        lines.append(Line(mine: true, text: said, at: Date()))
        thinking = true
        defer { thinking = false }
        var r = URLRequest(url: Brain.base.appendingPathComponent("chat"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["text": said])
        do {
            let (data, _) = try await net.data(for: r)
            let got = try JSONDecoder().decode(Answer.self, from: data)
            guard let answer = got.answer, !answer.isEmpty else {
                throw NSError(domain: "arisu", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: got.error ?? "she said nothing"])
            }
            lines.append(Line(mine: false, text: answer, at: Date()))
            failed = nil
        } catch {
            failed = error.localizedDescription
        }
        // Her answer moved the conversation, so the desk has new guesses.
        Task { await suggest() }
    }

    /// Her line said again straight after itself is drawn once. The desk
    /// stored "Good morning" three times a second apart (2026-10-02), one per
    /// "new" that arrived while the first was still being made; the stored
    /// thread stays as it is, the screen just does not repeat her.
    static func once(_ lines: [Line]) -> [Line] {
        var kept: [Line] = []
        for l in lines {
            if let last = kept.last, !l.mine, !last.mine, last.text == l.text { continue }
            kept.append(l)
        }
        return kept
    }

    /// A "new" already on its way. The two-finger double tap and the + can
    /// both fire while the desk is still composing the greeting, and each
    /// one it receives adds another greeting to the same thread.
    private var starting = false

    /// A clean thread. The old one stays in history; the desk decides what
    /// "new" means for her mind, which is why this is a POST and not a
    /// `lines.removeAll()`.
    func new() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        struct Fresh: Decodable { let greeting: String? }
        var r = URLRequest(url: Brain.base.appendingPathComponent("chat/new"))
        r.httpMethod = "POST"
        lines.removeAll()
        failed = nil
        // She opens it: hello and today's top three (Oscar, 2026-10-01).
        if let (data, _) = try? await net.data(for: r),
           let hello = (try? JSONDecoder().decode(Fresh.self, from: data))?.greeting, !hello.isEmpty {
            lines.append(Line(mine: false, text: hello, at: Date()))
        }
        Task { await suggest() }
    }

    /// Fresh suggestions. A failed or empty answer keeps what was showing,
    /// as the web chat does: a row that blanks on a slow model is worse than
    /// one that is a minute old.
    func suggest() async {
        guard let (data, _) = try? await net.data(from: Brain.base.appendingPathComponent("chat/suggest")),
              let got = try? JSONDecoder().decode(Suggestions.self, from: data),
              !got.isEmpty else { return }
        suggestions = got
    }

    /// A page made showable by the desk, the same reading a call's page gets
    /// (lain's GET /reader, server/reader.py). When the desk cannot be
    /// reached the sheet still opens, says so and offers Safari.
    func page(_ url: URL) async -> ShowPage {
        var c = URLComponents(string: "/reader")!
        c.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        // A page the desk could not read comes back as a 502 with the reason
        // in the same shape, which is worth showing as it is.
        if let at = c.url(relativeTo: Brain.base), let (data, _) = try? await net.data(from: at),
           let got = try? JSONDecoder().decode(ShowPage.self, from: data), !got.url.isEmpty {
            return got
        }
        return ShowPage(url: url.absoluteString, host: url.host(), mode: nil, title: nil, text: nil,
                        headlines: nil, ok: false, error: "The desk could not be reached to read this page.")
    }

    func loadSessions() async {
        guard let url = URL(string: "history", relativeTo: Brain.base) else { return }
        guard let (data, _) = try? await net.data(from: url),
              let got = try? JSONDecoder().decode(Sessions.self, from: data) else { return }
        sessions = got.sessions
    }

    /// One past conversation, read-only.
    func transcript(_ id: String) async -> [Line] {
        var c = URLComponents(url: Brain.base.appendingPathComponent("history"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let url = c.url, let (data, _) = try? await net.data(from: url),
              let got = try? JSONDecoder().decode(Thread.self, from: data) else { return [] }
        return got.messages.map(Self.line)
    }
}

/// The thread and the composer. The composer is the whole navigation of this
/// app now (Oscar, 2026-09-28): Send types at her, Voice hands the screen to
/// the hologram, and there is no mode toggle in the corner to find first.
struct ChatPane: View {
    @ObservedObject var chat: Chat
    /// Her state, so the composer can carry the same colour the room does.
    let phase: Color
    /// Set from the room's History button: show the sheet as soon as the
    /// chat appears, so one press crosses both.
    @Binding var openHistory: Bool
    /// Press Voice: the caller draws her instead of this.
    let toVoice: () -> Void
    /// A page from one of her lines, for the app's page sheet.
    var show: (ShowPage) -> Void = { _ in }
    /// The app's title row is above this view now, not over it.
    var topInset: CGFloat = 0
    /// lain's day, the same panel voice mode has beside her (13.0).
    var glance = Glance()
    /// What the conversation is about; the panel comes up lit for it.
    @Binding var focus: GlanceFocus?
    /// Held up by a tour stop, without touching his own setting.
    var shown = false

    /// Bubbles or terminal lines, the chat's own answer.
    @AppStorage("arisu.bubbles.chat") private var bubbles = true
    @State private var typing = ""
    @State private var showHistory = false
    /// The page being fetched for the sheet, so its chip can say so.
    @State private var opening: URL?
    /// The day panel, pinned open from its button. Kept: whether he reads
    /// the chat with his day beside it is a habit, not a moment.
    @AppStorage("arisu.glance.chat") private var glancePinned = false
    private var glanceUp: Bool { glancePinned || focus != nil || shown }
    @FocusState private var writing: Bool

    /// She is white, he is cyan -- the same rule the room's subtitles follow.
    private let cyan = Color.white
    private let mag = Skin.cyan

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                // Beside the thread when the pane is wide (landscape), above it
                // when it is not: a 320pt column would leave a portrait thread
                // too narrow to read.
                let wide = g.size.width >= 700
                let stack = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                                 : AnyLayout(VStackLayout(spacing: 0))
                stack {
                    if glanceUp && !wide { panel(width: g.size.width - 36) }
                    thread
                    if glanceUp && wide { panel(width: 320) }
                }
                .animation(.easeOut(duration: 0.3), value: glanceUp)
            }
            // Out of the way while she is thinking (16.0): the guesses were
            // made for her previous line, and a command tapped then is ignored.
            // Faded rather than removed, so the thread keeps its height: taking
            // the strip out and putting it back as her answer lands left the
            // thread an empty grid in the simulator.
            if !chat.suggestions.isEmpty {
                suggestRow
                    .opacity(chat.thinking ? 0 : 1)
                    .allowsHitTesting(!chat.thinking)
                    .transition(.opacity)
            }
            composer
        }
        .animation(.easeOut(duration: 0.25), value: chat.suggestions)
        .animation(.easeOut(duration: 0.25), value: chat.thinking)
        .padding(.top, topInset)
        .console(Skin.cyan, brackets: Skin.mag)
        // The same 10pt inset as Record and Deck, so the corners line up.
        .padding(10)
        // A two-finger double tap is a new conversation (Oscar, 2026-10-02).
        .background(MultiTap(touches: 2, taps: 2) { Task { await chat.new() } })
        .task { await chat.load() }
        // Every minute while the chat is on screen: the desk turns the
        // commands over every few minutes even when nobody types. The task
        // ends when the chat leaves the screen.
        .task {
            while !Task.isCancelled {
                await chat.suggest()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onAppear { if openHistory { showHistory = true; openHistory = false } }
        .sheet(isPresented: $showHistory) { ChatHistory(chat: chat) }
    }

    private func panel(width: CGFloat) -> some View {
        // Above a pane this wide -- landscape with the deck at half -- the
        // panel goes in two columns, so it takes a third of the thread rather
        // than two thirds (14.0).
        GlancePanel(glance: glance, focus: focus, width: width, columns: width >= 560)
            .padding(.top, 14).padding(.horizontal, 18)
            .tourSpot("chatGlance")
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var thread: some View {
        ScrollViewReader { scroll in
            threadBody(scroll)
        }
        .tourSpot("thread")
        // A double tap on the thread is voice (Oscar, 2026-10-02); on the
        // thread only, so a double tap in the composer still selects a word.
        .simultaneousGesture(TapGesture(count: 2).onEnded { toVoice() })
    }

    private func threadBody(_ scroll: ScrollViewProxy) -> some View {
        Group {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chat.lines) { bubble($0) }
                    if chat.thinking {
                        HStack(spacing: 8) {
                            ProgressView().tint(mag).scaleEffect(0.7)
                            Text("thinking")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(mag.opacity(0.8))
                        }
                        .id("thinking")
                    }
                    if let failed = chat.failed {
                        Text("! " + failed)
                            .font(Skin.mono(12))
                            .foregroundStyle(mag)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Pulled down past the top of the thread: the older conversations.
            .refreshable { showHistory = true }
            .onChange(of: chat.lines.count) { _, _ in rest(scroll) }
            .onChange(of: chat.thinking) { _, _ in rest(scroll) }
            // The keyboard takes the bottom of the thread, which is where the
            // newest lines are: once it is up, go back to them (Backlog, Arisu:
            // "With the keyboard up, the newest messages are the ones I see").
            .onChange(of: writing) { _, on in if on { rest(scroll, after: 400) } }
            // Any change of the thread's own size -- the iPad turned, the day
            // panel opened or closed above it, the deck's seam moved -- leaves
            // it resting on the newest line (14.0). Turning the iPad used to
            // leave it in the middle of an old answer, or on an empty grid
            // until it was scrolled.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in rest(scroll) }
            // The suggestions strip coming up takes the bottom of the thread
            // too; the resize alone was seen to leave the newest answer half
            // under it (15.0), so rest once its animation is over.
            .onChange(of: chat.suggestions.isEmpty) { _, _ in rest(scroll, after: 300) }
            .defaultScrollAnchor(.bottom)
        }
    }

    /// To the newest line, and once more when the layout has settled. The
    /// thread is lazy: rows it has not drawn have guessed heights, so one jump
    /// made while a rotation or the panel is still animating lands short --
    /// the second, a beat later, lands on the real end.
    private func rest(_ scroll: ScrollViewProxy, after ms: Int = 0) {
        Task {
            if ms > 0 { try? await Task.sleep(for: .milliseconds(ms)) }
            withAnimation { scroll.scrollTo("end", anchor: .bottom) }
            try? await Task.sleep(for: .milliseconds(450))
            scroll.scrollTo("end", anchor: .bottom)
        }
    }

    /// His on the right in magenta, hers on the left in cyan -- the same shape
    /// her subtitles have over the room, so the two modes read as one thread.
    private func bubble(_ line: Chat.Line) -> some View {
        HStack {
            // Terminal is a log: every line starts at the left margin, his
            // and hers alike (Oscar, 2026-09-29).
            if line.mine && bubbles { Spacer(minLength: 40) }
            HStack(alignment: .top, spacing: 6) {
                if line.spoken {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 9))
                        .foregroundStyle((line.mine ? mag : cyan).opacity(0.6))
                        .padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(conversationLinks(speaker(line.mine) + line.text))
                        .font(Skin.mono(15))
                        .foregroundStyle(line.mine ? mag : cyan)
                        .textSelection(.enabled)
                    if !line.mine { pages(line.text) }
                }
            }
            .opacity(line.spoken ? 0.72 : 1)
            .padding(.horizontal, bubbles ? 14 : 0)
            .padding(.vertical, bubbles ? 10 : 1)
            .background {
                if bubbles { Edge {
                    Rectangle()
                        .fill((line.mine ? mag : cyan).opacity(0.08))
                        .overlay(Rectangle()
                            .stroke((line.mine ? mag : cyan)
                                .opacity(line.spoken ? 0.25 : 0.45)))
                } }
            }
            // The Record panel's log row: a lit bar on the speaker's side.
            .edge(alignment: line.mine ? .trailing : .leading) {
                if bubbles {
                    let ink = line.mine ? mag : cyan
                    Rectangle().fill(ink).frame(width: 3).shadow(color: ink, radius: 4)
                }
            }
            if !line.mine || !bubbles { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity,
               alignment: (line.mine && bubbles) ? .trailing : .leading)
    }

    /// Under her line, one chip per page she linked (16.0, Backlog: "Arisu
    /// puts a page on screen inside her own tab"): the page in the app's own
    /// sheet, the same one a call opens, without starting a call. Tapping the
    /// link itself still goes to the browser.
    @ViewBuilder private func pages(_ text: String) -> some View {
        let urls = webLinks(text).map(\.0).reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
        if !urls.isEmpty {
            HStack(spacing: 6) {
                ForEach(urls.prefix(3), id: \.self) { url in
                    Button {
                        guard opening == nil else { return }
                        opening = url
                        Task {
                            let page = await chat.page(url)
                            opening = nil
                            show(page)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if opening == url {
                                ProgressView().tint(Skin.cyan).scaleEffect(0.6).frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                    .font(.system(size: 11))
                            }
                            Text(url.host() ?? url.absoluteString).font(Skin.mono(12, .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(Skin.cyan)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .raised(Skin.cyan, stroke: 0.45, fill: Color.black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .tourSpot("pageChip")
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "clock", label: "History", tint: Skin.off) { showHistory = true }
            IconButton(symbol: "plus", label: "New conversation", tint: Skin.off) {
                Task { await chat.new() }
            }
            TextField("", text: $typing, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(Skin.mono(15))
                .foregroundStyle(.white)
                .tint(mag)
                .focused($writing)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .raised(writing ? mag : .white, stroke: writing ? 0.7 : 0.14,
                        fill: Color.white.opacity(0.06))
                .overlay(alignment: .leading) {
                    if typing.isEmpty {
                        Text("say something")
                            .font(Skin.mono(15))
                            .foregroundStyle(.white.opacity(0.25))
                            .padding(.leading, 15)
                            .allowsHitTesting(false)
                    }
                }
            // The day beside the thread, lit while it is up (13.0).
            IconButton(symbol: "rectangle.leadinghalf.inset.filled", label: "Today",
                       tint: glanceUp ? Skin.cyan : Skin.off, lit: glanceUp) {
                // Closing closes it, even if the conversation brought it up.
                withAnimation {
                    if glanceUp { glancePinned = false; focus = nil } else { glancePinned = true }
                }
            }
            .tourSpot("chatGlanceButton")
            IconButton(symbol: "arrow.up", label: "Send",
                       tint: typing.isEmpty ? Skin.off : mag, lit: !typing.isEmpty, action: send)
            // The way into her voice. Her state colours it, so the button he
            // pressed to start talking is also the light that says she heard.
            IconButton(symbol: "waveform", label: "Voice", tint: phase, action: toVoice)
                .tourSpot("voiceButton")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        // With the pane's 10pt inset, 28pt off the edge like the deck's keys.
        .padding(.bottom, 18)
        .tourSpot("composer")
    }

    /// Above the composer, as on the web chat (Oscar, 2026-10-02): commands
    /// for the moment, then his likely answers with the most likely one lit.
    /// One line each that scrolls sideways, so the strip is always the same
    /// height and the thread above it never jumps; when it first appears the
    /// thread's own resize rests it on the newest line (14.0).
    private var suggestRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !chat.suggestions.commands.isEmpty {
                chips {
                    ForEach(chat.suggestions.commands, id: \.self) { c in
                        // A command is a line he would have typed: sent as his.
                        chip(Text("> ").foregroundStyle(Skin.cyan.opacity(0.6)) + Text(c.label),
                             ink: Skin.cyan, stroke: 0.45) {
                            guard !chat.thinking else { return }
                            typing = c.text
                            send()
                        }
                    }
                }
                .tourSpot("suggestCommands")
            }
            if !chat.suggestions.replies.isEmpty {
                chips {
                    ForEach(Array(chat.suggestions.replies.enumerated()), id: \.offset) { i, r in
                        // A reply goes into the field for him to change or
                        // send; it is never sent for him.
                        chip(Text(r), ink: i == 0 ? Skin.mag : .white.opacity(0.82),
                             stroke: i == 0 ? 1 : 0.18) {
                            typing = r
                            writing = true
                        }
                    }
                }
                .tourSpot("suggestReplies")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func chips<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Room inside the clip for the lit chip's glow.
            HStack(spacing: 6) { content() }.padding(.vertical, 4)
        }
    }

    /// The web chat's chip: monospaced, a thin edge in its own colour on a
    /// dark plate, both gone in free form so only the words are left.
    private func chip(_ label: Text, ink: Color, stroke: Double,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(Skin.mono(13, .semibold)).foregroundStyle(ink).lineLimit(1)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .raised(ink, stroke: stroke, fill: Color.black.opacity(0.45))
        }
        .buttonStyle(.plain)
    }

    private func send() {
        let said = typing
        typing = ""
        Task { await chat.send(said) }
    }

}

/// Every conversation, chat and voice, newest first. Reading one is reading;
/// nothing here resumes a thread, because the desk has exactly one live
/// conversation and picking an old one would quietly end it.
struct ChatHistory: View {
    @ObservedObject var chat: Chat
    @Environment(\.dismiss) private var dismiss
    @State private var open: [Chat.Line] = []
    @State private var title = ""

    private let cyan = Color.white
    private let mag = Skin.cyan

    var body: some View {
        NavigationStack {
            Group {
                if open.isEmpty { list } else { transcript }
            }
            .background(Grid(tint: Skin.cyan).ignoresSafeArea())
            .fontDesign(.monospaced)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if open.isEmpty {
                        Button("Close") { dismiss() }
                    } else {
                        Button("Back") { open = []; title = "" }
                    }
                }
            }
            .navigationTitle(open.isEmpty ? "Conversations" : title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .task { await chat.loadSessions() }
    }

    private var list: some View {
        List(chat.sessions) { s in
            Button {
                title = when(s.start)
                Task { open = await chat.transcript(s.id) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: s.kind == "voice" ? "mic.fill" : "terminal")
                            .font(.system(size: 11))
                            .foregroundStyle(s.kind == "voice" ? cyan : mag)
                        Text(when(s.start))
                            .font(Skin.mono(12))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("\(s.count)")
                            .font(Skin.mono(11))
                            .foregroundStyle(Skin.ink.opacity(0.7))
                    }
                    Text(s.preview)
                        .font(Skin.mono(13))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
            }
            .listRowBackground(Edge { Rectangle().fill(Skin.cyan.opacity(0.05))
                .overlay(Rectangle().stroke(Skin.cyan.opacity(0.3))) })
        }
        .scrollContentBackground(.hidden)
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(open) { line in
                    Text(conversationLinks(line.text))
                        .font(Skin.mono(14))
                        .foregroundStyle(line.mine ? mag : cyan)
                        .frame(maxWidth: .infinity,
                               alignment: line.mine ? .trailing : .leading)
                }
            }
            .padding(18)
        }
    }

    private func when(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .hour().minute())
    }
}

/// Her line as it should read. Links are tappable, `**bold**` is bold and a
/// `* ` at the start of a line is a bullet: she writes Markdown in the typed
/// chat (the email list, 2026-10-02) and the raw asterisks made it hard to
/// read (16.0). Nothing else is interpreted -- an underscore in a file name or
/// a lone asterisk stays as she wrote it, and no HTML is ever rendered.
func conversationLinks(_ text: String) -> AttributedString {
    let listed = text.replacingOccurrences(of: #"(?m)^(\s*)\* "#, with: "$1• ",
                                           options: .regularExpression)
    // Pairs only: an odd ** at the end is left as written.
    var parts = listed.components(separatedBy: "**")
    if parts.count % 2 == 0 {
        let tail = parts.removeLast()
        parts[parts.count - 1] += "**" + tail
    }
    var result = AttributedString()
    for (i, part) in parts.enumerated() {
        var piece = AttributedString(part)
        if i % 2 == 1 { piece.inlinePresentationIntent = .stronglyEmphasized }
        result += piece
    }
    let plain = parts.joined()
    for (url, range) in webLinks(plain) {
        guard let start = AttributedString.Index(range.lowerBound, within: result),
              let end = AttributedString.Index(range.upperBound, within: result) else { continue }
        result[start..<end].link = url
        result[start..<end].underlineStyle = .single
    }
    return result
}

/// Made once: building a detector is the slow part, and every bubble on
/// screen asks for one each time the chat is drawn (seen in a sample, 16.0).
private let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

/// The http and https addresses in a line, in order, with where they are.
func webLinks(_ text: String) -> [(URL, Range<String.Index>)] {
    guard let detector = linkDetector else { return [] }
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
        guard let url = match.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let range = Range(match.range, in: text) else { return nil }
        return (url, range)
    }
}

/// A tap with several fingers, which SwiftUI cannot express. Watches the
/// window but only answers inside the view it sits behind, so a two-finger
/// tap on the deck is not a new chat.
struct MultiTap: UIViewRepresentable {
    let touches: Int
    let taps: Int
    let action: () -> Void

    func makeUIView(context: Context) -> Host { Host(touches: touches, taps: taps, action: action) }
    func updateUIView(_ v: Host, context: Context) { v.action = action }

    final class Host: UIView, UIGestureRecognizerDelegate {
        var action: () -> Void
        private let tap = UITapGestureRecognizer()

        init(touches: Int, taps: Int, action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            tap.numberOfTouchesRequired = touches
            tap.numberOfTapsRequired = taps
            tap.cancelsTouchesInView = false
            tap.delegate = self
            tap.addTarget(self, action: #selector(fire))
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            tap.view?.removeGestureRecognizer(tap)
            window?.addGestureRecognizer(tap)
        }

        @objc private func fire() { action() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            bounds.contains(touch.location(in: self))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
