import Foundation

/// What the desk sends back for one utterance.
struct Snap: Decodable {
    let seq: Int
    let line: String
    let mood: String
    let action: String
    let heard: String?
    let ignored: Bool?
    /// The desk thinks he had not finished the sentence, and has deliberately
    /// not answered it.
    let incomplete: Bool?
}

/// What the desk hands over so the phone can open a realtime session: a
/// client secret good for a few minutes, with her persona and all 37 tools
/// already fixed to it. The OpenAI key itself never leaves the Mac.
struct LiveToken: Decodable {
    let value: String
    let url: String
    let model: String
}

/// What she is like, as the desk holds it. Three dials from 0 to 1, a voice,
/// and a free-text note he can write in his own words. `voices` is the desk's
/// list rather than the app's, so a voice the API stops accepting disappears
/// from the picker instead of leaving her mute.
struct Persona: Codable {
    var warmth: Double
    var playfulness: Double
    var brevity: Double
    var voice: String
    var notes: String
    var voices: [String]?
}

/// architect, over Tailscale. The brain is unchanged from the web version --
/// same `/arisu/listen`, same JSON -- so everything Arisu knows how to do
/// (planner, board, habits, diary, the lot) works here on day one.
final class Brain {
    static let base = URL(string: "https://architect-server.tailaa64e9.ts.net:8443/arisu/")!

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        // Her one tool is a whole turn of Hermes' conversation on architect,
        // not an MCP call: 3.5-7.5s warm, 17s measured on a quota failover,
        // and worse if the agent has to build itself. lain prewarms it at boot
        // so that cost is not paid here, but the budget still has to allow it.
        c.timeoutIntervalForRequest = 120
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    /// `force` means: answer it even if it sounds unfinished. Sent when he
    /// has gone quiet long enough that the rest is not coming.
    func listen(_ wav: Data, force: Bool = false) async throws -> Snap {
        var c = URLComponents(url: Brain.base.appendingPathComponent("listen"),
                              resolvingAgainstBaseURL: false)!
        if force { c.queryItems = [URLQueryItem(name: "force", value: "1")] }
        var r = URLRequest(url: c.url!)
        r.httpMethod = "POST"
        r.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        r.httpBody = wav
        let (data, resp) = try await session.data(for: r)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Snap.self, from: data)
    }

    /// Mint a session for the speech-to-speech path. The desk decides which
    /// models are allowed; anything else it does not recognise falls back to
    /// its own default rather than being spent on.
    func realtimeToken(model: String) async throws -> LiveToken {
        var c = URLComponents(url: Brain.base.appendingPathComponent("realtime"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "model", value: model)]
        let (data, resp) = try await session.data(from: c.url!)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(LiveToken.self, from: data)
    }

    /// What she is like right now.
    func persona() async throws -> Persona {
        let (data, resp) = try await session.data(
            from: Brain.base.appendingPathComponent("persona"))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Persona.self, from: data)
    }

    /// Change part of what she is like. Sent as a patch, not a whole object,
    /// so two settings screens open at once cannot undo each other.
    @discardableResult
    func setPersona(_ patch: [String: Any]) async throws -> Persona {
        var r = URLRequest(url: Brain.base.appendingPathComponent("persona"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: patch)
        let (data, resp) = try await session.data(for: r)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Persona.self, from: data)
    }

    /// Run one of her tools on the desk, where the MCP bridge lives.
    ///
    /// `rawArgs` is the argument JSON exactly as the model produced it, and
    /// the answer goes back to her as free text -- neither is decoded here,
    /// because 36 tools have 36 shapes and this end does not care about any
    /// of them.
    func tool(name: String, rawArgs: String) async throws -> String {
        var r = URLRequest(url: Brain.base.appendingPathComponent("tool"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let escaped = String(data: try JSONEncoder().encode(name), encoding: .utf8) ?? "\"\""
        let args = rawArgs.isEmpty ? "{}" : rawArgs
        r.httpBody = Data("{\"name\":\(escaped),\"args\":\(args)}".utf8)
        let (data, _) = try await session.data(for: r)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// One line into /tmp/arisu-face.log on the desk. The phone has no
    /// console anyone can reach, so this is the only way to see what the
    /// realtime session is actually doing.
    func debug(_ note: [String: String]) {
        guard let body = try? JSONSerialization.data(withJSONObject: note)
        else { return }
        var r = URLRequest(url: Brain.base.appendingPathComponent("debug"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        session.dataTask(with: r).resume()
    }

    /// Her current line without saying anything -- used to pick up the idle
    /// remarks the desk makes on its own timer.
    func state() async throws -> Snap {
        let (data, _) = try await session.data(from: Brain.base.appendingPathComponent("state"))
        return try JSONDecoder().decode(Snap.self, from: data)
    }

    /// The same thing, held open until she actually says something new.
    ///
    /// The desk parks the request until its sequence number passes `since`,
    /// up to 25 seconds, then answers with whatever it has. That is what
    /// carries the aside she makes while a tool runs: it exists a second
    /// before the answer does, and there is no other way back to the phone
    /// in the middle of a request it is already waiting on.
    func state(since: Int) async throws -> Snap {
        var c = URLComponents(url: Brain.base.appendingPathComponent("state"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "wait", value: "1"),
                        URLQueryItem(name: "since", value: String(since))]
        let (data, _) = try await session.data(from: c.url!)
        return try JSONDecoder().decode(Snap.self, from: data)
    }
}
