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
            lines = try JSONDecoder().decode(Thread.self, from: data).messages.map(Self.line)
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
    }

    /// A clean thread. The old one stays in history; the desk decides what
    /// "new" means for her mind, which is why this is a POST and not a
    /// `lines.removeAll()`.
    func new() async {
        var r = URLRequest(url: Brain.base.appendingPathComponent("chat/new"))
        r.httpMethod = "POST"
        _ = try? await net.data(for: r)
        lines.removeAll()
        failed = nil
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
    /// The app's title row is above this view now, not over it.
    var topInset: CGFloat = 0

    /// Bubbles or terminal lines, the chat's own answer.
    @AppStorage("arisu.bubbles.chat") private var bubbles = true
    @State private var typing = ""
    @State private var showHistory = false
    @FocusState private var writing: Bool

    /// She is white, he is cyan -- the same rule the room's subtitles follow.
    private let cyan = Color.white
    private let mag = Skin.cyan

    var body: some View {
        VStack(spacing: 0) {
            thread
            composer
        }
        .padding(.top, topInset)
        .console(Skin.cyan, brackets: Skin.mag)
        // The same 10pt inset as Record and Deck, so the corners line up.
        .padding(10)
        .task { await chat.load() }
        .onAppear { if openHistory { showHistory = true; openHistory = false } }
        .sheet(isPresented: $showHistory) { ChatHistory(chat: chat) }
    }

    private var thread: some View {
        ScrollViewReader { scroll in
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
            .onChange(of: chat.lines.count) { _, _ in
                withAnimation { scroll.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: chat.thinking) { _, _ in
                withAnimation { scroll.scrollTo("end", anchor: .bottom) }
            }
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
                Text(conversationLinks((bubbles ? "" : (line.mine ? "> " : "")) + line.text))
                    .font(Skin.mono(15))
                    .foregroundStyle(line.mine ? mag : cyan)
                    .textSelection(.enabled)
            }
            .opacity(line.spoken ? 0.72 : 1)
            .padding(.horizontal, bubbles ? 14 : 0)
            .padding(.vertical, bubbles ? 10 : 1)
            .background {
                if bubbles {
                    Rectangle()
                        .fill((line.mine ? mag : cyan).opacity(0.08))
                        .overlay(Rectangle()
                            .stroke((line.mine ? mag : cyan)
                                .opacity(line.spoken ? 0.25 : 0.45)))
                }
            }
            // The Record panel's log row: a lit bar on the speaker's side.
            .overlay(alignment: line.mine ? .trailing : .leading) {
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
            IconButton(symbol: "arrow.up", label: "Send",
                       tint: typing.isEmpty ? Skin.off : mag, lit: !typing.isEmpty, action: send)
            // The way into her voice. Her state colours it, so the button he
            // pressed to start talking is also the light that says she heard.
            IconButton(symbol: "waveform", label: "Voice", tint: phase, action: toVoice)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        // With the pane's 10pt inset, 28pt off the edge like the deck's keys.
        .padding(.bottom, 18)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Skin.cyan.opacity(0.35)),
                 alignment: .top)
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
            .listRowBackground(Rectangle().fill(Skin.cyan.opacity(0.05))
                .overlay(Rectangle().stroke(Skin.cyan.opacity(0.3))))
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

/// Detect web links without interpreting Markdown or HTML in the conversation.
func conversationLinks(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return result
    }
    for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let url = match.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let range = Range(match.range, in: text),
              let start = AttributedString.Index(range.lowerBound, within: result),
              let end = AttributedString.Index(range.upperBound, within: result) else { continue }
        result[start..<end].link = url
        result[start..<end].underlineStyle = .single
    }
    return result
}
