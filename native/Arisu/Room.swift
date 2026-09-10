import Foundation
import UIKit

/// The other screens in the house, and whose turn it is.
///
/// One device with one microphone needs none of this. Three do: they hear the
/// same sentence, all three answer it, and each one hears the other two
/// answering and treats that as a new question. The desk arbitrates instead --
/// `server/room.py` holds who is here, whose microphone is live, and who is
/// allowed to be speaking right now -- and this is the client half.
///
/// Three rules, all of them enforced on the desk rather than here, because a
/// rule that lives in the app is a rule that a device with an old build gets
/// to ignore:
///
///   * **One ear.** In a group exactly one device streams its microphone. The
///     others keep their sessions open and hear the room as text.
///   * **One mouth.** A device takes the floor before it speaks and gives it
///     back when it stops. The rest wait.
///   * **One answer.** The desk names which device replies to each sentence,
///     so the others are given the words as context and stay quiet.
///
/// The transport is the same long poll the rest of lain uses: one request held
/// open, woken the moment anything changes.
@MainActor
final class Room: ObservableObject {
    struct Member: Decodable, Identifiable, Equatable {
        let device: String
        let name: String
        let character: String
        var id: String { device }
    }

    @Published private(set) var mode = "solo"
    @Published private(set) var listener = ""
    /// Who is speaking right now, as the desk sees it. Empty means the room
    /// is quiet and anyone may start.
    @Published private(set) var holder = ""
    @Published private(set) var members: [Member] = []
    @Published private(set) var reachable = false

    /// Which of them this screen is showing. Held on the device and not on the
    /// desk, because in a room the whole point is that the four screens are
    /// four different people -- the desk's active character is only the
    /// default a fresh install starts from.
    @Published var character = "" {
        didSet {
            guard character != oldValue, !character.isEmpty else { return }
            UserDefaults.standard.set(character, forKey: Room.characterKey)
            Task { await self.join() }
            onCharacter?(character)
        }
    }

    var isGroup: Bool { mode == "group" }
    var isListener: Bool { listener == device }
    /// Somebody else is mid-sentence. The listener stops feeding its
    /// microphone while this is true, which is the multi-device version of the
    /// echo problem `realtime.INTERRUPT` already had to solve for one device.
    var othersSpeaking: Bool { !holder.isEmpty && holder != device }

    /// He said something, and which device the desk wants to answer it.
    var onHeard: ((String, String) -> Void)?
    /// One of them said something, for the others to hear as context.
    var onSaid: ((String, String, String) -> Void)?
    /// Mode, listener or floor moved.
    var onChange: (() -> Void)?
    /// This screen is a different character now, so the session has to be
    /// reminted -- the identity is baked in at mint time and cannot be
    /// changed on a live socket.
    var onCharacter: ((String) -> Void)?

    private static let deviceKey = "arisu.room.device"
    private static let characterKey = "arisu.room.character"

    /// Stable for the life of the install. `identifierForVendor` would do the
    /// same job and is not ours to keep -- it changes when the last app from
    /// this vendor is deleted, which is a reinstall away.
    let device: String = {
        let d = UserDefaults.standard
        if let got = d.string(forKey: Room.deviceKey), !got.isEmpty { return got }
        let made = UUID().uuidString
        d.set(made, forKey: Room.deviceKey)
        return made
    }()

    /// What he calls this device. His own name for it, from Settings, which is
    /// the only label that means anything when four of them are on a shelf.
    let name = UIDevice.current.name

    private let base = Brain.base.appendingPathComponent("room")
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        // Longer than the desk's own poll timeout, or every idle poll would
        // come back as a client error rather than as "nothing happened".
        c.timeoutIntervalForRequest = 45
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()
    private var pump: Task<Void, Never>?
    private var since = 0

    init() {
        character = UserDefaults.standard.string(forKey: Room.characterKey) ?? ""
    }

    // MARK: - membership

    func start() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            await self?.join()
            while !Task.isCancelled { await self?.poll() }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        Task { _ = try? await self.post(["op": "leave", "device": device]) }
    }

    @discardableResult
    private func join() async -> Bool {
        let got = try? await post(["op": "join", "device": device,
                                   "name": name, "character": character])
        guard let got else { reachable = false; return false }
        apply(got)
        // The desk resolves an empty or deleted character to whoever is on it,
        // and that answer is the one this screen should show from now on.
        if character.isEmpty,
           let mine = members.first(where: { $0.device == device }) {
            character = mine.character
        }
        return true
    }

    // MARK: - the two settings

    func set(mode value: String) {
        Task { if let got = try? await post(["op": "mode", "device": device,
                                             "mode": value]) { apply(got) } }
    }

    /// Move the one live microphone to this device.
    func listenHere() {
        Task { if let got = try? await post(["op": "listener",
                                             "device": device]) { apply(got) } }
    }

    // MARK: - the words

    /// Only the listener calls this, and only in a group: it is the one device
    /// that heard him, so it is the one that can tell the others what he said.
    func report(heard text: String) {
        guard isGroup, isListener else { return }
        Task { _ = try? await post(["op": "heard", "device": device, "text": text]) }
    }

    /// She finished a sentence. The others need it or their next turn is a
    /// reply to half a conversation.
    func report(said text: String) {
        guard isGroup else { return }
        Task { _ = try? await post(["op": "said", "device": device, "text": text]) }
    }

    // MARK: - the floor

    /// Ask for the right to speak. False means somebody else has it and this
    /// device should wait to be told it was given back.
    func takeFloor() async -> Bool {
        guard isGroup else { return true }
        guard let got = try? await post(["op": "floor", "device": device,
                                         "want": "take"]) else { return false }
        apply(got)
        return got["holding"] as? Bool ?? false
    }

    func giveFloor() {
        guard isGroup else { return }
        Task { if let got = try? await post(["op": "floor", "device": device,
                                             "want": "give"]) { apply(got) } }
    }

    // MARK: - transport

    private func poll() async {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "device", value: device),
                        URLQueryItem(name: "since", value: String(since)),
                        URLQueryItem(name: "wait", value: "1")]
        do {
            let (data, resp) = try await session.data(from: c.url!)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let top = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw URLError(.badServerResponse) }
            reachable = true
            if let state = top["room"] as? [String: Any] { apply(state) }
            for ev in top["events"] as? [[String: Any]] ?? [] { handle(ev) }
            // Dropped for being away: rejoin rather than poll a room this
            // device is no longer in, which would otherwise be silent forever.
            if !members.contains(where: { $0.device == device }) { await join() }
        } catch {
            reachable = false
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func handle(_ ev: [String: Any]) {
        if let seq = ev["seq"] as? Int { since = max(since, seq) }
        switch ev["kind"] as? String {
        case "heard":
            // The listener already heard him through its own microphone and
            // has the words in its own session; handing them back would say
            // everything twice.
            let from = ev["device"] as? String ?? ""
            guard from != device else {
                if let answer = ev["answer"] as? String, answer == device {
                    onHeard?("", device)
                }
                return
            }
            onHeard?(ev["text"] as? String ?? "", ev["answer"] as? String ?? "")
        case "said":
            guard (ev["device"] as? String ?? "") != device else { return }
            onSaid?(ev["name"] as? String ?? "",
                    ev["character"] as? String ?? "",
                    ev["text"] as? String ?? "")
        default:
            onChange?()
        }
    }

    private func apply(_ state: [String: Any]) {
        let wasGroup = isGroup, wasListener = isListener, wasHolder = holder
        if let m = state["mode"] as? String { mode = m }
        if let l = state["listener"] as? String { listener = l }
        if let f = state["floor"] as? String { holder = f }
        if let raw = state["members"],
           let data = try? JSONSerialization.data(withJSONObject: raw),
           let got = try? JSONDecoder().decode([Member].self, from: data) {
            members = got
        }
        if wasGroup != isGroup || wasListener != isListener || wasHolder != holder {
            onChange?()
        }
    }

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        var r = URLRequest(url: base)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: r)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let got = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw URLError(.badServerResponse) }
        return got
    }
}
