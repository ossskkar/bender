import SwiftUI

/// The deck: his Mac's buttons, on the iPad.
///
/// The macropad was retired on 2026-09-26 and this is where its useful half
/// went. The Mac runs `arisu/deck/deck.py`, which still holds the pad's action
/// executor and the pad's own 36 bindings; this screen draws them and presses
/// them. Nothing is executed here -- the iPad sends an id and the Mac decides
/// what that id means, which is the whole reason the run endpoint takes an id
/// and never an action.
///
/// Reached over the tailnet through `tailscale serve` on the Mac, so it works
/// from the sofa and not at all from outside the tailnet.
enum DeckAPI {
    /// The Mac, over the tailnet. Port 8443 is a `tailscale serve` rule that
    /// already existed and pointed at a dead 127.0.0.1:8887 -- the deck listens
    /// there, so this needed no new rule and no change to his machine
    /// (2026-09-26). Tailnet only, never a funnel; see deck.py's docstring.
    static let base = URL(string: "https://oscars-macbook-pro.tailaa64e9.ts.net:8443/")!
}

/// How loud Spotify is on the Mac, streamed by the deck at 30 Hz, so she moves
/// with his music while she is idle (Oscar, 2026-10-01). Zero when the Mac,
/// the meter or the music is not there.
@MainActor final class MacMusic: ObservableObject {
    @Published private(set) var level = 0.0

    /// Holds the stream open until cancelled, reconnecting after a drop.
    func listen() async {
        let url = DeckAPI.base.appendingPathComponent("deck/music")
        while !Task.isCancelled {
            if let (bytes, _) = try? await URLSession.shared.bytes(from: url) {
                do {
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        level = Double(line.dropFirst(6)) ?? 0
                    }
                } catch {}
            }
            level = 0
            try? await Task.sleep(for: .seconds(5))
        }
        level = 0
    }
}

/// Anything JSON, for the two fields of an `http` action that are not strings.
/// It exists so that saving a button cannot quietly drop part of it.
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// One thing the Mac can do. Every field the deck's executor understands, so a
/// button he edits here goes back whole. Optionals are omitted on encode, which
/// is what keeps `{"type":"shell","cmd":...}` from growing six null keys.
struct DeckAction: Codable, Equatable {
    var type = "shell"
    var cmd: String?
    var url: String?
    var script: String?
    var text: String?
    var paste: Bool?
    var keys: String?
    var title: String?
    var method: String?
    var headers: [String: String]?
    var body: JSONValue?
    var steps: [DeckAction]?

    static let types = ["shell", "applescript", "open", "keys", "text",
                        "notify", "http", "compound"]

    /// What the button does, in one line, for the row under its label.
    var summary: String {
        switch type {
        case "shell": return cmd ?? ""
        case "applescript": return (script ?? "").replacingOccurrences(of: "\n", with: " ")
        case "open": return url ?? ""
        case "keys": return keys ?? ""
        case "text": return (paste == true ? "type " : "copy ") + (text ?? "")
        case "notify": return title ?? ""
        case "http": return ((method ?? "GET") + " " + (url ?? ""))
        case "compound": return "\(steps?.count ?? 0) steps"
        default: return type
        }
    }

    /// The kind of thing the button does, as the icon on it: input text, a
    /// shortcut, open an app, a link, a process (Oscar, 2026-09-30). A
    /// compound is named by its first step -- typing into Claude is input.
    var symbol: String {
        switch type {
        case "text": return "character.cursor.ibeam"
        case "keys": return "command"
        case "open": return "link"
        case "applescript": return (script ?? "").contains("activate") ? "macwindow" : "gearshape.2"
        case "notify": return "bell"
        case "compound": return steps?.first?.symbol ?? "square.stack"
        default: return "gearshape.2"
        }
    }
}

struct DeckButton: Codable, Equatable, Identifiable {
    var id: String
    var group = ""
    var label = ""
    var icon = ""
    /// What a long press says the button does. Optional so a store without
    /// it still decodes.
    var about: String?
    var action = DeckAction()

    /// The one button every deck ends with, bottom right: sleep the Mac and
    /// black out the iPad (Oscar, 2026-09-30).
    static let sleepID = "sleep"
}

/// The set, and the two things he does to it: press one, save them all.
@MainActor final class Deck: ObservableObject {
    @Published var buttons: [DeckButton] = []
    @Published var failed: String?
    @Published var loading = false
    /// The deck of whatever is frontmost on the Mac, and the app's own name
    /// for the rail to show. Empty means nothing on the Mac matches a group,
    /// which is the signal to leave his choice alone.
    @Published var front = ""
    @Published var frontApp = ""
    /// The applications he switches between, from the Mac's own list.
    @Published var apps: [String] = []
    /// How the last press of each button went, and when. The rail colours the
    /// button itself from this -- cyan while it runs, green when it worked,
    /// red when it did not -- instead of printing a receipt underneath
    /// (Oscar, 2026-09-29). It clears itself, because a button that stays
    /// green is a button that is lying by the time he looks again.
    @Published var outcome: [String: Bool] = [:]

    private func mark(_ id: String, _ ok: Bool) {
        outcome[id] = ok
        Task { [weak self] in
            // Long enough to catch out of the corner of an eye; a failure
            // stays longer because it is the one he has to act on.
            try? await Task.sleep(for: .seconds(ok ? 2.5 : 7))
            guard let self, self.outcome[id] == ok else { return }
            self.outcome[id] = nil
        }
    }

    /// The id that is running, and the last answer, for the row to show.
    @Published var running: String?
    @Published var said: (id: String, ok: Bool, detail: String)?

    /// Eight seconds, not the sixty URLSession gives by default. The rail is on
    /// screen the whole time now, so a Mac that accepts the connection and then
    /// says nothing -- which is what a deck blocked on a macOS file-access
    /// prompt looks like -- has to end as a message rather than a spinner that
    /// never stops (2026-09-27).
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        return URLSession(configuration: c)
    }()

    /// Every application has its own deck, named after it (Oscar,
    /// 2026-10-01): his apps in his order, each even before it has actions,
    /// then any group that is not an app (lain).
    var groups: [String] {
        var seen = apps
        for b in buttons where b.id != DeckButton.sleepID && !b.group.isEmpty && !seen.contains(b.group) {
            seen.append(b.group)
        }
        return seen
    }

    /// What the Mac is doing, every couple of seconds. Cheap on purpose: the
    /// answer is two short strings and the buttons are not re-sent.
    func watchFront() async {
        struct Answer: Decodable { let app: String?; let group: String? }
        while !Task.isCancelled {
            if let (data, _) = try? await session.data(
                from: DeckAPI.base.appendingPathComponent("deck/front")),
               let got = try? JSONDecoder().decode(Answer.self, from: data) {
                frontApp = got.app ?? ""
                front = got.group ?? ""
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        struct Answer: Decodable {
            let buttons: [DeckButton]
            let front: String?
            let apps: [String]?
        }
        do {
            let (data, _) = try await session.data(
                from: DeckAPI.base.appendingPathComponent("deck"))
            let got = try JSONDecoder().decode(Answer.self, from: data)
            buttons = got.buttons
            front = got.front ?? front
            apps = got.apps ?? []
            failed = nil
        } catch {
            failed = "The Mac did not answer. Is the deck running, and is this "
                   + "device on the tailnet?"
        }
    }

    /// Bring one of his applications to the front of the Mac. The rail
    /// follows the Mac, so pressing this also changes which deck is up --
    /// one press moves both machines.
    func open(app: String) async {
        struct Answer: Decodable { let ok: Bool?; let detail: String?; let error: String? }
        running = app
        defer { running = nil }
        var r = URLRequest(url: DeckAPI.base.appendingPathComponent("deck/app"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["name": app])
        guard let (data, _) = try? await session.data(for: r),
              let got = try? JSONDecoder().decode(Answer.self, from: data) else {
            said = (app, false, "the Mac did not answer")
            mark(app, false)
            return
        }
        if let wrong = got.error { said = (app, false, wrong); mark(app, false) }
        else { mark(app, true) }
    }

    func run(_ b: DeckButton) async {
        struct Answer: Decodable { let ok: Bool?; let detail: String?; let error: String? }
        Usage.bump(b.id)
        running = b.id
        defer { running = nil }
        var r = URLRequest(url: DeckAPI.base.appendingPathComponent("deck/run"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["id": b.id])
        do {
            let (data, _) = try await session.data(for: r)
            let got = try JSONDecoder().decode(Answer.self, from: data)
            let ok = got.ok ?? false
            said = (b.id, ok, got.detail ?? got.error ?? "")
            mark(b.id, ok)
        } catch {
            said = (b.id, false, "the Mac did not answer")
            mark(b.id, false)
        }
    }

    var sleep: DeckButton? { buttons.first { $0.id == DeckButton.sleepID } }

    /// The whole set, every time: the Mac's `POST /deck` replaces it, so an
    /// add, an edit, a delete and a drag are all this one call. The apps go
    /// too, for their order; the Mac refuses any other change to that list.
    func save() async -> String? {
        struct Answer: Decodable { let ok: Bool?; let error: String? }
        var r = URLRequest(url: DeckAPI.base.appendingPathComponent("deck"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let buttons: [DeckButton]; let apps: [String] }
        r.httpBody = try? JSONEncoder().encode(Body(buttons: buttons, apps: apps))
        do {
            let (data, _) = try await session.data(for: r)
            let got = try JSONDecoder().decode(Answer.self, from: data)
            return got.ok == true ? nil : (got.error ?? "the Mac refused it")
        } catch {
            return "the Mac did not answer"
        }
    }
}

/// How much he uses each button, so the deck can put the ones he reaches for
/// first (Oscar, 2026-10-01). A press adds one; every two weeks the score
/// halves, so a habit he dropped stops holding the best seat. On this iPad
/// only: it is his hand on this screen being learned.
enum Usage {
    private static let key = "arisu.deck.usage"
    private static let halfLife = 14.0 * 86_400

    private static var all: [String: [Double]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func score(_ id: String, now: Date = Date()) -> Double {
        guard let s = all[id], s.count == 2 else { return 0 }
        return s[0] * pow(0.5, (now.timeIntervalSince1970 - s[1]) / halfLife)
    }

    static func bump(_ id: String, now: Date = Date()) {
        all[id] = [score(id, now: now) + 1, now.timeIntervalSince1970]
    }

    /// Most used first; never used keep the order he gave them.
    static func ranked(_ buttons: [DeckButton]) -> [DeckButton] {
        let now = Date()
        return buttons.enumerated()
            .sorted { a, b in
                let sa = score(a.element.id, now: now), sb = score(b.element.id, now: now)
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)
    }
}
