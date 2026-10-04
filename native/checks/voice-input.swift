import Foundation

@MainActor final class StubBrain {
    var calls = [(String, String)]()
    var delay: UInt64 = 0
    func tool(name: String, rawArgs: String) async throws -> String {
        calls.append((name, rawArgs))
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return "{\"result\":{\"answer\":\"The test lamp is blue.\"}}"
    }
}
@MainActor final class ToolFixture {
    var socket: NSObject? = NSObject()
    let brain = StubBrain()
    var role = (group: false, unused: false)
    var voiceInputs = VoiceInputs()
    var responseInputs = [String: String]()
    var invalidPlans = Set<String>()
    var sourceAnswers = [String: [(String, String)]](), sourceAnswer = ""
    var toolsOut = 0, ownResponses = 0
    var connected = true, hushed = false
    var replyAt: Date?
    var awaiting = Set<String>()
    var work = [String: Int](), latestWork: String?
    var openPlans = Set<String>(), owedPlans = Set<String>()
    var onMood: ((String, String) -> Void)?
    var sent = [[String: Any]](), flushes = 0
    func send(_ value: [String: Any]) { sent.append(value) }
    func flush() { flushes += 1 }
    func answer() {}
    func superseded() {}
    func bind(_ text: String? = nil, id: String = "u", response: String = "p") {
        _ = voiceInputs.commit(id); responseInputs[response] = id
        work[response] = 1; latestWork = response; awaiting.insert("c")
        if let text { voiceInputs.transcribe(id, text: text) }
    }
    // Actual production methods are inserted by the runner.
    PRODUCTION_METHODS
}

@main struct Checks {
    @MainActor static func main() async {
        var input = VoiceInputs()
        input.transcribe("a", text: "  Arisu, ask Hermes about Gemini.  ")
        assert(input.commit("a"))
        assert(input.text("a") == "  Arisu, ask Hermes about Gemini.  ")
        assert(input.takeHeard("a") == "  Arisu, ask Hermes about Gemini.  ")
        assert(input.takeHeard("a") == nil)
        input.transcribe("a", text: "rewritten")
        assert(input.text("a") == "  Arisu, ask Hermes about Gemini.  ")
        assert(input.commit("b")); assert(!input.commit("a")); assert(input.latest == "b")
        assert(input.text("a") == nil && input.takeHeard("a") == nil)
        input.transcribe("b", text: nil); input.transcribe("b", text: "late")
        assert(input.text("b") == nil && input.finished("b"))
        input = VoiceInputs(); assert(input.latest == nil)
        for i in 0..<100 { _ = input.commit("u\(i)") }
        assert(input.count <= 64)
        let exact = "  Set the test lamp blue, Arisu.  "
        let f = ToolFixture(); f.bind(exact)
        await f.runTool(name: "think", callID: "c", args: "{\"question\":\"resume an old task\"}", responseID: "p")
        let body = try! JSONSerialization.jsonObject(with: Data(f.brain.calls[0].1.utf8)) as! [String: Any]
        assert(body["question"] as? String == exact)
        assert(f.sent.count == 2 && f.toolsOut == 0)
        let delayed = ToolFixture(); delayed.bind()
        let task = Task { await delayed.runTool(name: "ask_hermes", callID: "c", args: "{}", responseID: "p") }
        try? await Task.sleep(nanoseconds: 100_000_000)
        assert(delayed.brain.calls.isEmpty)
        delayed.voiceInputs.transcribe("u", text: exact); await task.value
        assert(delayed.brain.calls.count == 1)
        for kind in ["failed", "empty", "stale", "cancelled", "unbound", "quiet-mention"] {
            let bad = ToolFixture(); bad.bind()
            switch kind {
            case "failed": bad.voiceInputs.transcribe("u", text: nil)
            case "empty": bad.voiceInputs.transcribe("u", text: "   ")
            case "stale": _ = bad.voiceInputs.commit("new")
            case "cancelled": bad.invalidPlans.insert("p")
            case "unbound": bad.responseInputs.removeAll()
            default: bad.voiceInputs.transcribe("u", text: "The room is quiet.")
            }
            await bad.runTool(name: kind == "quiet-mention" ? "go_quiet" : "think", callID: "c", args: "{}", responseID: "p")
            assert(bad.brain.calls.isEmpty, kind); assert(bad.flushes == 0 && !bad.hushed)
            assert(bad.sent.first?["item"] != nil)
            if kind == "stale" || kind == "cancelled" { assert(bad.sent.count == 1) }
        }
        let timeout = ToolFixture(); timeout.bind()
        await timeout.runTool(name: "think", callID: "c", args: "{\"question\":\"inferred\"}", responseID: "p")
        assert(timeout.brain.calls.isEmpty)
        timeout.voiceInputs.transcribe("u", text: exact); assert(timeout.voiceInputs.text("u") == nil)
        let replacement = ToolFixture(); replacement.bind()
        let waiting = Task { await replacement.runTool(name: "think", callID: "c", args: "{}", responseID: "p") }
        try? await Task.sleep(nanoseconds: 100_000_000)
        replacement.socket = NSObject(); replacement.toolsOut = 7
        await waiting.value; assert(replacement.brain.calls.isEmpty && replacement.sent.isEmpty)
        assert(replacement.toolsOut == 7)
        let dispatched = ToolFixture(); dispatched.bind(exact); dispatched.brain.delay = 100_000_000
        let old = Task { await dispatched.runTool(name: "think", callID: "c", args: "{}", responseID: "p") }
        try? await Task.sleep(nanoseconds: 50_000_000); dispatched.socket = NSObject()
        await old.value; assert(dispatched.brain.calls.count == 1 && dispatched.sent.isEmpty)
        let url = "https://example.com/a(b)?q=one%20two&x=2#part"
        let display = ToolFixture(); display.bind(exact)
        display.rememberAnswer("{\"result\":{\"answer\":\"The unit is probably faulty; unconfirmed. \(url)\"}}", responseID: "p", callID: "c")
        assert(webLinks(display.sourceAnswer).map { $0.0.absoluteString } == [url])
        display.speakReply()
        let instruction = (display.sent.last?["response"] as? [String: Any])?["instructions"] as? String ?? ""
        assert(instruction.contains("probably") && instruction.contains("unconfirmed") && !instruction.contains(url))
        let saved = display.sourceAnswer
        display.invalidPlans.insert("p")
        display.rememberAnswer("{\"result\":{\"answer\":\"wrong https://example.com/stale\"}}", responseID: "p", callID: "d")
        assert(display.sourceAnswer == saved)
        let quiet = ToolFixture(); quiet.bind("Arisu, please be quiet.")
        await quiet.runTool(name: "go_quiet", callID: "c", args: "{}", responseID: "p")
        assert(quiet.brain.calls.count == 1 && quiet.hushed && quiet.flushes == 1)
        let group = ToolFixture(); group.role.group = true
        await group.runTool(name: "think", callID: "c", args: "{\"question\":\"room input\"}", responseID: "room")
        assert(group.brain.calls.first?.1 == "{\"question\":\"room input\"}")
        print("PASS: actual native tool forwarding, exact captions, delay/failure/timeout, stale/cancelled input, reconnect and dispatched work, explicit quiet, group contract and bounds")
    }
}
