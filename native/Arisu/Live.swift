import AVFoundation
import Foundation
import os

/// Speech to speech, straight to OpenAI.
///
/// The whisper path asks four questions in a row -- has he stopped talking,
/// what did he say, what should she say, what does that sound like -- and the
/// first one is answered with a volume meter. That is what "it cuts me off"
/// and "sometimes I can interrupt her" both were: amplitude cannot tell a
/// pause for thought from the end of a sentence, and cannot tell his voice
/// from the echo of hers.
///
/// Here the model hears the room itself. It decides when he is done from what
/// he is saying, and interruption is an event rather than a threshold. The ear,
/// the gate, the amend window and the hang all go away.
///
/// What does not change: her persona, her 36 tools and her body all still live
/// on the desk. The desk mints the session (`/arisu/realtime`) with the persona
/// and tool definitions already fixed to it, and runs any tool she calls
/// (`/arisu/tool`). The phone never holds the OpenAI key and cannot reconfigure
/// her.
@MainActor
final class Live: ObservableObject {
    @Published private(set) var connected = false
    /// He stopped her, as opposed to the socket being briefly away. The
    /// settings screen needs it: a sample cannot play through a session that
    /// is deliberately shut, and a dead button with no reason is what "it
    /// doesn't work" means.
    @Published private(set) var paused = false
    @Published private(set) var speaking = false      // she is talking
    @Published private(set) var hearing = false       // he is talking
    /// A tool is out. On this path that means `think` -- a whole turn of
    /// Hermes on architect, which is seconds rather than milliseconds, so it
    /// is the one wait long enough that the screen has to account for it.
    @Published private(set) var thinking = false
    /// Tools out. A flag was not enough: two tool calls in one turn, or a turn
    /// abandoned when the socket was replaced, could leave it stuck on -- and
    /// a permanent "thinking" is worse than none, because it stops meaning
    /// anything. Anything that ends a turn zeroes this.
    private var toolsOut = 0 {
        didSet {
            thinking = toolsOut > 0
            watchThinking()
        }
    }
    /// `think` calls out at the desk and not yet answered, by call id. Not
    /// `toolsOut`: her own audio zeroes that, and the short line she says
    /// before thinking is audio that can arrive while the call is still out.
    private var awaiting = Set<String>()
    /// Responses this client asked for and has not yet seen created. Any other
    /// response is the server answering on its own -- see `response.created`.
    private var ownResponses = 0
    /// A tool that never came back must not leave her thinking forever.
    ///
    /// `runTool` decrements in a `defer`, so the count cannot leak on its own
    /// -- but the desk's budget for one Hermes turn is two minutes, and a
    /// socket replaced mid-call abandons the task holding that `defer`. Either
    /// way the face sits in the thinking animation with nothing behind it,
    /// which is what he saw. The count is the truth until it is plainly stale.
    private var thinkingWatch: Task<Void, Never>?
    private func watchThinking() {
        thinkingWatch?.cancel()
        guard toolsOut > 0 else { thinkingWatch = nil; return }
        thinkingWatch = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, let self, self.toolsOut > 0 else { return }
            self.brain.debug(["ev": "thinking-stuck"])
            self.toolsOut = 0
        }
    }
    /// One turn at a time instead of an open mic: nothing is streamed until he
    /// holds the button, and the turn ends when he lets go rather than when a
    /// model decides he has finished. He asked for this after the open mic
    /// answered half a sentence -- and it is the only way to say something
    /// long, or to think mid-sentence, without being interrupted.
    @Published private(set) var pushing = false
    /// Whether the open mic is off entirely. Set from the button; when true,
    /// the tap runs (the meter still moves) but nothing reaches her until
    /// `pushing`.
    @Published var turnMode = false {
        didSet { if turnMode != oldValue { applyTurnMode() } }
    }
    /// The microphone, off, without ending the conversation.
    ///
    /// Distinct from both the other two controls and worth saying why. The
    /// waveform button ends the conversation: the socket goes, the tap comes
    /// down, nothing is heard or billed. The record button is push-to-talk: the
    /// mic is live and she is simply waiting to be handed a turn. This is the
    /// third thing -- stay connected, keep her context, and let the room be
    /// private for a minute. He can pick the conversation back up mid-thought
    /// rather than starting a new one.
    ///
    /// The tap keeps running while muted so the meter still moves. That is the
    /// only honest way to show a microphone that is alive and going nowhere,
    /// and it is the same choice `turnMode` already made.
    @Published var muted = false {
        didSet { if muted != oldValue { applyMute() } }
    }
    @Published private(set) var status = ""
    @Published var level: Float = 0

    /// She called `set_mood`: the hologram's colour and animation.
    var onMood: ((String, String) -> Void)?
    /// Her words, as they are spoken -- for the caption under the pet.
    var onTranscript: ((String) -> Void)?
    /// What he said, once the model has transcribed it.
    var onHeard: ((String) -> Void)?

    /// Which realtime model to ask the desk for. Changing it takes effect on
    /// the next connection, so the socket is dropped when it changes.
    var model = "gpt-realtime-2.1-mini"

    /// Which of them this screen is. Baked into the session at mint time, so a
    /// change only lands on the next connection -- `Pet` drops the socket.
    var character = ""

    /// What the room says this device may do right now.
    ///
    /// Three states rather than a flag, because they fail differently. Not in
    /// a group at all: the session works the way it always has. In a group but
    /// not the ear: the microphone must reach nothing, and everything this
    /// screen knows arrives as text. Blocked: somebody else is mid-sentence,
    /// so even the ear stops feeding -- her voice coming out of another phone
    /// two feet away is indistinguishable to a VAD from him starting to talk,
    /// which is the same collision `realtime.INTERRUPT` was turned off for.
    struct Role: Equatable {
        var group = false
        var listener = false
        var blocked = false
    }
    var role = Role() {
        didSet { if role != oldValue { applyInput() } }
    }

    /// True when nothing this microphone hears may reach a model.
    private var silenced: Bool {
        muted || (role.group && (!role.listener || role.blocked))
    }

    /// The room, when there is one. Set by `Pet`.
    weak var room: Room?

    /// Seconds of nobody talking before the socket is dropped. The session is
    /// billed by the minute it is open, not by the minute it is used: at a ten
    /// hour day an always-open one is $100+/month. Nil keeps it open forever,
    /// which is the right setting only while testing.
    var idleClose: TimeInterval? = 90

    private let brain = Brain()
    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    // Her jaw follows HER voice, measured off the player, not off the
    // microphone. Driving it from the input tap is what made her mouth move
    // while *he* talked and sit still while she spoke.
    //
    // An expander rather than a fixed gain, ported from the browser client:
    // her level is whatever the realtime API and the speaker give it, and a
    // gain turns that straight into how far her mouth opens. Measured there
    // end to end, a fixed gain put the jaw at 0.10 on a quiet stream and 0.54
    // on a loud one; against a running peak a 12x change in level gives the
    // same face.
    private static let voicePeakFloor: Float = 0.02   // below this it is silence
    private static let voiceFloorRatio: Float = 0.5   // shut at half the peak
    /// Peak decay per second, not per callback: the tap fires on the audio
    /// buffer size, which is the hardware's business and not a constant.
    private static let voicePeakDecay: Float = 0.953
    private var voicePeak: Float = Live.voicePeakFloor
    private let rate: Double = 24_000          // the only rate `audio/pcm` takes
    /// What OpenAI sends: 24k mono. Her audio is decoded into this.
    private var playFormat: AVAudioFormat!
    /// What the hardware actually runs at. The player is connected in this
    /// format rather than hers -- under voice-processing I/O a mixer input at
    /// a rate the hardware is not running can leave the whole graph stalled,
    /// started but never pulling, which takes the input tap down with it.
    private var mixFormat: AVAudioFormat!
    private var toMix: AVAudioConverter?
    private var converter: AVAudioConverter?
    /// Held so `end()` can take it off again. Re-registering on every restart
    /// would leave one observer per stop/start, each rebuilding the graph.
    private var configObserver: NSObjectProtocol?

    private var lastVoice = Date()
    private var idleTimer: Task<Void, Never>?
    /// Set while the socket is deliberately shut for idleness, so the tap
    /// knows to listen for a reason to open it again.
    private var dormant = false
    /// Set when *he* stopped her, which is a different thing from idle.
    /// Dormant means "asleep, wake me"; this means "off". Every path that
    /// would otherwise bring the socket back on its own checks it, because
    /// there are three of them -- the tap's gate, the reconnect after a
    /// failed mint, and the receive loop's error branch -- and a stop that
    /// only closed the socket would be undone by whichever fired first.
    private var stopped = false
    /// `stopped`, in a form URLSession's callback thread can read. The receive
    /// loop re-arms itself over there rather than on the main actor, so the one
    /// flag it has to consult cannot be main-actor isolated.
    private let halted = OSAllocatedUnfairLock(initialState: false)
    private var floor: Float = 0
    /// Buffers of hers scheduled but not yet out of the speaker. `response.done`
    /// says the *server* stopped sending, which on a long answer is seconds
    /// before she stops being audible; this is the only thing that knows when
    /// she has actually finished talking.
    private var pending = 0

    // MARK: - the socket

    func begin() {
        stopped = false
        paused = false
        halted.withLock { $0 = false }
        guard socket == nil else { return }
        Task { await connect() }
    }

    /// Start the session again, so anything fixed to it at mint time -- her
    /// instructions, her voice -- is picked up. There is no way to change
    /// either on a live session, which is why changing her voice from the
    /// settings sheet has to come through here.
    func reconnect() async {
        guard !stopped else { return }
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        player.stop()
        pending = 0
        speaking = false
        toolsOut = 0
        awaiting.removeAll()
        ownResponses = 0
        await connect()
    }

    /// Reconnect and have her say one line, so a setting can be heard before
    /// it is lived with.
    ///
    /// Through her own session rather than a synthesiser on the desk: the
    /// OpenAI key is not permitted to call audio/speech, and going through the
    /// session means the preview is the actual voice carrying the actual
    /// instructions rather than an approximation of both.
    func preview(_ line: String) async {
        guard !stopped, !line.isEmpty else { return }
        await reconnect()
        guard connected else { return }
        // A one-off response with its own instructions, rather than a message
        // pushed into the conversation. Two reasons: she is told to think
        // before every turn he addresses to her, so a message asking her to
        // read a line got thought about instead of read; and `tool_choice`
        // none is the only way to say that with any certainty. It also leaves
        // no trace in the conversation, which a sample should not.
        ownResponses += 1
        send(["type": "response.create",
              "response": ["instructions":
                            "Say exactly this out loud, word for word, and "
                            + "nothing else: \"" + line + "\"",
                           "output_modalities": ["audio"],
                           "tool_choice": "none"]])
    }

    /// Swap models mid-conversation. The session carries her whole context,
    /// so this is a new conversation, not a new voice on the old one.
    func use(model name: String) {
        guard name != model else { return }
        model = name
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        player.stop()
        pending = 0
        Task { await connect() }
    }

    private func connect() async {
        guard !stopped else { return }
        // Audio first, and its failure is terminal rather than retried: a
        // socket that cannot be fed is a session being paid for in silence,
        // which is exactly what the last build did.
        do { try startAudio() }
        catch {
            status = "no mic"
            brain.debug(["ev": "audio-failed", "text": "\(error)"])
            return
        }
        do {
            let token = try await brain.realtimeToken(model: model,
                                                      character: character)
            var r = URLRequest(url: URL(string: token.url)!)
            r.setValue("Bearer " + token.value, forHTTPHeaderField: "Authorization")
            let ws = session.webSocketTask(with: r)
            socket = ws
            ws.resume()
            connected = true
            dormant = false
            status = ""
            lastVoice = Date()
            listen()
            startIdleWatch()
            // Every session is minted with the open mic, so a reconnect while
            // muted or in turn mode has to say so again or she starts
            // answering the room. Mute first: it is the stricter of the two and
            // it is what applyMute would have sent anyway.
            // One call rather than three: mute, turn mode and the room all
            // decide the same field, and sending them in sequence let the
            // looser one land last and undo the stricter.
            applyInput()
        } catch {
            connected = false
            status = "no session"
            // A failed mint is usually the desk being asleep, not a bug worth
            // burning the battery on. Try again on a slow beat.
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !dormant && !stopped { await connect() }
        }
    }

    /// Drop the socket but keep the microphone: the tap stays up so his next
    /// word can bring the session back. Ending the engine too would mean
    /// missing the first half-second of whatever he says.
    private func sleepSession() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        dormant = true
        speaking = false
        toolsOut = 0
        player.stop()
        pending = 0
        voicePeak = Live.voicePeakFloor
        level = 0
        status = "idle"
    }

    /// Off, not asleep: the socket goes, the tap comes down and the engine
    /// stops, so nothing is recorded, nothing is streamed and nothing is
    /// billed. `begin()` builds all of it back.
    func end() {
        stopped = true
        paused = true
        halted.withLock { $0 = true }
        dormant = false
        speaking = false
        hearing = false
        toolsOut = 0
        pushing = false
        level = 0
        player.stop()
        pending = 0
        idleTimer?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        voicePeak = Live.voicePeakFloor
        engine.inputNode.removeTap(onBus: 0)
        player.removeTap(onBus: 0)
        engine.stop()
        // `startAudio()` returns early while `playFormat` is set, so clearing
        // it is what makes the next `begin()` actually rebuild the graph.
        // Without this the socket reopened onto a stopped engine and she sat
        // there connected and deaf -- sessions in the log, not one mic frame.
        playFormat = nil
        toMix = nil
        converter = nil
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        // Hand the microphone back, so stopped is something the system agrees
        // with: the recording indicator goes out.
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startIdleWatch() {
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                guard let gap = self.idleClose, self.connected, !self.speaking
                else { continue }
                if Date().timeIntervalSince(self.lastVoice) > gap {
                    self.sleepSession()
                }
            }
        }
    }

    private func listen() {
        guard let socket else { return }
        arm(socket)
    }

    /// Re-arms on URLSession's own callback thread, deliberately. Waiting for
    /// the main actor before asking for the next frame put hundreds of audio
    /// deltas a second in front of `receive()`, and the one event that has to
    /// feel instant -- `input_audio_buffer.speech_started`, which *is*
    /// barge-in -- queued behind her own voice. So the loop checks `halted`
    /// here, re-arms straight away, and sends only the frame to the main actor.
    ///
    /// Re-arming is still the loop's own heartbeat, and still the thing that
    /// checks whether he stopped her: without that check a stop closed the
    /// socket while the receive loop kept queueing itself.
    private nonisolated func arm(_ socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                Task { @MainActor in
                    guard self.socket != nil, !self.stopped else { return }
                    self.connected = false
                    self.socket = nil
                    await self.connect()
                }
            case .success(let message):
                guard !self.halted.withLock({ $0 }) else { return }
                self.arm(socket)
                guard case .string(let text) = message else { return }
                Task { @MainActor in self.handle(text) }
            }
        }
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { [weak self] err in
            guard let err else { return }
            Task { @MainActor in self?.sendFailed(err) }
        }
    }

    /// The first failure only. A broken socket fails every frame of audio,
    /// and 23 of those a second would bury the log it is meant to explain.
    private var toldOfSendFailure = false
    private func sendFailed(_ err: Error) {
        guard !toldOfSendFailure else { return }
        toldOfSendFailure = true
        brain.debug(["ev": "send-failed", "text": "\(err)"])
    }

    /// Raw JSON, for the one message whose body is already a JSON string and
    /// must not be re-encoded -- a tool's result on its way back to her.
    private func sendRaw(_ text: String) {
        socket?.send(.string(text)) { _ in }
    }

    // MARK: - what comes back

    private func handle(_ text: String) {
        // Stopped is not idle. Frames already in the socket when he pressed
        // pause keep arriving for a moment, and every one of them used to move
        // her face, her transcript and her hands as though nothing happened --
        // which is what made a paused pet look like a running one.
        guard !stopped else { return }
        guard let data = text.data(using: .utf8),
              let ev = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = ev["type"] as? String else { return }

        // Every event except the audio itself, which arrives in hundreds of
        // chunks and would say nothing a count does not.
        if type != "response.output_audio.delta" {
            brain.debug(["ev": type,
                         "err": (ev["error"] as? [String: Any])
                                .flatMap { $0["message"] as? String } ?? ""])
        }

        switch type {
        case "response.output_audio.delta":
            // She is talking, so whatever she was thinking about is finished.
            // The count is the truth in the normal case; this is what catches
            // the abnormal one, and it costs nothing to be sure.
            toolsOut = 0
            if let b64 = ev["delta"] as? String { play(b64) }
            if !speaking { brain.debug(["ev": "audio-began"]) }
            speaking = true

        case "response.output_audio.done", "response.done":
            // Only if the speaker is already dry. Otherwise she is still
            // talking and `speaking` has to stay true, or the idle watch and
            // the interrupt path both believe a silent socket means silence.
            if pending == 0 { speaking = false }

        case "response.output_audio_transcript.done":
            if let t = ev["transcript"] as? String {
                onTranscript?(t)
                // The other screens cannot hear her -- only the ear has a live
                // microphone, and it is deaf while she talks -- so the room is
                // how what she just said reaches them.
                room?.report(said: t)
                brain.debug(["ev": "said", "text": String(t.prefix(200))])
            }

        case "conversation.item.input_audio_transcription.completed":
            if let t = ev["transcript"] as? String {
                onHeard?(t)
                brain.debug(["ev": "heard", "text": String(t.prefix(200))])
            }

        case "input_audio_buffer.speech_started":
            // He has started talking. The server is already cancelling her
            // response; this throws away the audio of it that is queued here,
            // which is the part he would otherwise still hear.
            hearing = true
            lastVoice = Date()
            // Unconditionally. This used to be gated on `speaking`, which
            // `response.done` had already cleared while several seconds of her
            // audio were still queued here -- so interrupting late in a long
            // answer threw nothing away, she talked over him to the end, and
            // then answered the thing he had said underneath her.
            flush()

        case "input_audio_buffer.speech_stopped":
            hearing = false
            lastVoice = Date()

        case "response.function_call_arguments.done":
            let name = ev["name"] as? String ?? ""
            let callID = ev["call_id"] as? String ?? ""
            let args = ev["arguments"] as? String ?? "{}"
            if name != "set_mood" { awaiting.insert(callID) }
            Task { await self.runTool(name: name, callID: callID, args: args) }

        case "response.created":
            // Something he said -- more words, an "hm", noise the server took
            // for speech -- started a reply of its own while `think` was still
            // out. That reply cannot know the answer, so it made one up, and
            // then she answered again when `think` came back: two different
            // answers to one question (face log, 2026-09-12). His words are
            // already in the conversation, so the reply that follows `think`
            // covers them; this one is cancelled before it says anything.
            if ownResponses > 0 {
                ownResponses -= 1
            } else if !awaiting.isEmpty {
                var cancel: [String: Any] = ["type": "response.cancel"]
                if let id = (ev["response"] as? [String: Any])?["id"] as? String {
                    cancel["response_id"] = id
                }
                send(cancel)
                brain.debug(["ev": "cancelled-extra"])
            }

        case "error":
            let err = ev["error"] as? [String: Any]
            status = (err?["message"] as? String) ?? "error"
            // A response.create refused because one is already running never
            // produces a `response.created`, so it must not stay counted.
            if status.contains("active response"), ownResponses > 0 {
                ownResponses -= 1
            }

        default:
            break
        }
    }

    // MARK: - one turn at a time

    /// Tell her end which way the microphone works now.
    ///
    /// Turn detection has to go off, not just quiet: with semantic VAD still
    /// listening, the burst that arrives when he lets go looks like a whole
    /// utterance and she would answer it twice -- once because the server
    /// decided he stopped, once because we asked.
    private func applyTurnMode() { applyInput() }

    /// How this session treats its microphone, decided in one place.
    ///
    /// Four things have an opinion -- the mute button, turn mode, whether this
    /// device is the room's ear, and whether somebody else is speaking -- and
    /// they all write the same field. Deciding them separately is how a mute
    /// used to be undone by a mode change arriving a frame later.
    ///
    /// The group case turns `create_response` off even on the ear. In a room
    /// the desk names who answers each sentence, so a session that answered
    /// what it heard by itself would be a fourth voice nobody asked for.
    private func applyInput() {
        pushing = false
        guard connected else { return }
        if silenced {
            hearing = false
            send(["type": "session.update",
                  "session": ["type": "realtime",
                              "audio": ["input": ["turn_detection": NSNull()]]]])
            // Whatever was captured before this is not hers to answer.
            send(["type": "input_audio_buffer.clear"])
            return
        }
        let detection: Any = turnMode
            ? NSNull()
            : ["type": "semantic_vad",
               "eagerness": "low",
               "create_response": !role.group,
               "interrupt_response": false] as [String: Any]
        send(["type": "session.update",
              "session": ["type": "realtime",
                          "audio": ["input": ["turn_detection": detection]]]])
    }

    /// Tell her end that the room has gone quiet, or come back.
    ///
    /// Turn detection goes off for the same reason it does in turn mode, and
    /// then some: with semantic VAD still running, unmuting after a silence
    /// hands the server a discontinuity it reads as the end of an utterance,
    /// and she answers a sentence that was never spoken to her. Unmuting
    /// restores whichever mode the buttons actually say, so the two controls
    /// cannot fight over the session.
    private func applyMute() { applyInput() }

    /// He is holding the button. Anything of hers still playing stops, because
    /// starting to talk is starting to talk however it was signalled.
    func startTurn() {
        guard turnMode, connected, !pushing, !muted else { return }
        flush()
        pushing = true
        hearing = true
        send(["type": "input_audio_buffer.clear"])
    }

    /// He let go. Commit what was said and ask for one answer.
    func endTurn() {
        guard pushing else { return }
        pushing = false
        hearing = false
        lastVoice = Date()
        send(["type": "input_audio_buffer.commit"])
        ownResponses += 1
        send(["type": "response.create"])
    }

    // MARK: - the room

    /// Put words this session never heard into it, as though it had.
    ///
    /// The speaker is named in the text rather than carried in a field: the
    /// realtime schema has one user role and no notion of a room, so the only
    /// place "who said this" can survive is the sentence itself. Without it a
    /// character answers every remark as though he had made it, and thanks him
    /// for things another character said.
    func hear(_ text: String, from who: String) {
        guard connected, !text.isEmpty else { return }
        let line = who.isEmpty ? text : "\(who) said: \(text)"
        send(["type": "conversation.item.create",
              "item": ["type": "message",
                       "role": "user",
                       "content": [["type": "input_text", "text": line]]]])
    }

    /// Say something, once the room allows it.
    ///
    /// The floor is asked for before the response rather than after, because
    /// after is too late: the audio starts arriving within a few hundred
    /// milliseconds and two devices that both decided to speak are already
    /// talking over each other by the time either finds out. A refusal waits
    /// for the room to go quiet rather than giving up -- being told to answer
    /// and then not answering is the one outcome that reads as broken.
    func answer() {
        guard connected else { return }
        Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(25)
            while Date() < deadline {
                if await self.room?.takeFloor() ?? true {
                    self.ownResponses += 1
                    self.send(["type": "response.create"])
                    return
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            self.brain.debug(["ev": "floor-timeout"])
        }
    }

    // MARK: - her hands, which are on the desk

    private func runTool(name: String, callID: String, args: String) async {
        var output = "{\"ok\":true}"
        let isBody = name == "set_mood"
        if !isBody { toolsOut += 1 }
        defer { if !isBody { toolsOut = max(0, toolsOut - 1) } }
        if isBody {
            if let d = args.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                onMood?(o["mood"] as? String ?? "calm",
                        o["action"] as? String ?? "idle")
            }
        } else {
            output = (try? await brain.tool(name: name, rawArgs: args))
                     ?? "{\"error\":\"desk unreachable\"}"
        }
        // `output` is free text, so the desk's JSON goes back verbatim rather
        // than being decoded into something Swift has a type for.
        let item: [String: Any] = [
            "type": "conversation.item.create",
            "item": ["type": "function_call_output",
                     "call_id": callID,
                     "output": output],
        ]
        awaiting.remove(callID)
        send(item)
        // `set_mood` is her face, not an answer. Asking for a response after it
        // made her reply twice to one question: once for the mood call and once
        // for the thinking call, because she routinely makes both in a turn.
        // Only the tool that actually fetched something gets a new response.
        // Through the room rather than straight at the socket: a tool answer
        // is still an answer, and one that skipped the floor would be the one
        // way a device could start talking over another.
        if !isBody { answer() }
    }

    // MARK: - audio

    private func startAudio() throws {
        guard playFormat == nil else { return }   // already running
        let session = AVAudioSession.sharedInstance()
        // .voiceChat is what turns on the system echo canceller. Without it
        // she hears herself and holds her own turn open forever.
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: rate, channels: 1,
                                   interleaved: false)

        // Turning voice processing on rebuilds the I/O unit underneath the
        // engine, which invalidates every connection made around it and stops
        // the engine -- after `start()` has already returned without throwing.
        // That is why three builds reported a running engine that had in fact
        // stopped before the first buffer. The graph has to be rebuilt when it
        // happens, so it is built in one place and that place is called again.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine,
            queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rebuild() }
            }
        try buildGraph()
    }

    /// The whole graph, from nothing: voice processing, the player, the tap.
    /// Idempotent, because a configuration change can fire at any moment and
    /// the answer to it is always to do this again.
    private func buildGraph() throws {
        let input = engine.inputNode
        // Best effort, and loudly so. Enabling it on the input node turns on
        // the shared voice-processing unit for both directions.
        do { try input.setVoiceProcessingEnabled(true) }
        catch { brain.debug(["ev": "vp-failed", "text": "\(error)"]) }

        // Read after enabling: turning voice processing on changes it.
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "Live", code: 2)   // session not live yet
        }
        mixFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: inFormat.sampleRate, channels: 1,
                                  interleaved: false)
        toMix = AVAudioConverter(from: playFormat, to: mixFormat)
        converter = AVAudioConverter(from: inFormat, to: playFormat)
        guard let converter, let format = playFormat, let mixFormat else {
            throw NSError(domain: "Live", code: 1)
        }

        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: mixFormat)

        // Her own voice, tapped where it is played rather than where it is
        // scheduled -- scheduling runs seconds ahead of the speaker, and a
        // mouth that leads the audio reads worse than one that does nothing.
        player.removeTap(onBus: 0)
        player.installTap(onBus: 0, bufferSize: 1024,
                          format: player.outputFormat(forBus: 0)) {
            [weak self] buf, _ in
            self?.heardSelf(buf)
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) {
            [weak self] buf, _ in
            self?.capture(buf, with: converter, to: format)
        }

        engine.prepare()
        try engine.start()
        player.play()

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            self.brain.debug(["ev": "engine",
                              "text": "running \(self.engine.isRunning) "
                                      + "taps \(self.taps)"])
        }
        brain.debug(["ev": "audio-up",
                     "text": "in \(inFormat.sampleRate)/\(inFormat.channelCount)ch "
                             + "vp \(input.isVoiceProcessingEnabled)"])
    }

    /// The engine was taken apart underneath us. Put it back.
    private func rebuild() {
        guard playFormat != nil, !engine.isRunning else { return }
        brain.debug(["ev": "rebuild"])
        do { try buildGraph() }
        catch { brain.debug(["ev": "rebuild-failed", "text": "\(error)"]) }
    }

    /// One block from the microphone: up to her if the socket is open, and
    /// otherwise only loud enough to decide whether to open it again.
    private nonisolated func capture(_ buf: AVAudioPCMBuffer,
                                     with converter: AVAudioConverter,
                                     to format: AVAudioFormat) {
        // Counted before anything can bail, so the log can tell a dead
        // microphone from a live one whose audio is being dropped here.
        guard let pcm = Live.resample(buf, with: converter, to: format) else {
            Task { @MainActor in self.meter(nil) }
            return
        }
        var sum: Float = 0
        for x in pcm { sum += x * x }
        let rms = (sum / Float(max(pcm.count, 1))).squareRoot()

        var bytes = Data(capacity: pcm.count * 2)
        for x in pcm {
            let c = max(-1, min(1, x))
            let s = Int16(c < 0 ? c * 32768 : c * 32767)
            withUnsafeBytes(of: s.littleEndian) { bytes.append(contentsOf: $0) }
        }
        let b64 = bytes.base64EncodedString()

        Task { @MainActor in
            // Deliberately NOT `self.level` -- that is her jaw, and it is
            // driven by `heardSelf` off her own playback. This rms is only
            // ever used to decide whether somebody said something.
            self.meter(rms)

            if self.dormant {
                // Asleep: the only question is whether that was a voice. The
                // same floor-following gate the whisper ear used, and for the
                // same reason -- a fixed threshold triggers all night.
                self.floor = self.floor == 0 ? rms : self.floor * 0.995 + rms * 0.005
                if !self.stopped,
                   rms > max(0.006, self.floor * 2.6) { await self.connect() }
                return
            }
            guard self.connected else { return }
            // Muted outranks everything: no audio leaves this device, whether
            // the mic is open or a turn is being held. In a room this also
            // covers every screen that is not the ear, and the ear itself
            // while another one is talking.
            guard !self.silenced else { return }
            // In turn mode the tap keeps running -- the meter is how he knows
            // the microphone is alive -- but the audio goes nowhere until he
            // is actually holding the button down.
            guard !self.turnMode || self.pushing else { return }
            self.send(["type": "input_audio_buffer.append", "audio": b64])
        }
    }

    /// Whether the tap is running at all, and how loud the room is according
    /// to it -- the two facts that separate "the microphone is dead" from
    /// "the microphone is fine and the audio is going nowhere".
    private var taps = 0
    private var dropped = 0
    private var loudest: Float = 0
    private var meterSince = Date()
    /// `nil` means the tap fired and the conversion to 24k failed.
    private func meter(_ rms: Float?) {
        taps += 1
        if let rms { loudest = max(loudest, rms) } else { dropped += 1 }
        guard Date().timeIntervalSince(meterSince) > 3 else { return }
        brain.debug(["ev": "mic",
                     "text": "taps \(taps) dropped \(dropped) "
                             + "peak \(String(format: "%.4f", loudest)) "
                             + "sent \(connected && !dormant)"])
        taps = 0; dropped = 0; loudest = 0; meterSince = Date()
    }

    /// The same conversion as `resample`, kept as a buffer because the
    /// player schedules buffers rather than arrays.
    private nonisolated static func resampleBuffer(
            _ buf: AVAudioPCMBuffer, with converter: AVAudioConverter,
            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(
            Double(buf.frameLength) * format.sampleRate / buf.format.sampleRate + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { return nil }
        var done = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            done = true
            status.pointee = .haveData
            return buf
        }
        return err == nil ? out : nil
    }

    private nonisolated static func resample(_ buf: AVAudioPCMBuffer,
                                             with converter: AVAudioConverter,
                                             to format: AVAudioFormat) -> [Float]? {
        let capacity = AVAudioFrameCount(
            Double(buf.frameLength) * format.sampleRate / buf.format.sampleRate + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { return nil }
        var done = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            done = true
            status.pointee = .haveData
            return buf
        }
        guard err == nil, let ch = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// Her voice, 24k PCM16, resampled to whatever the hardware wants and
    /// scheduled as it arrives.
    private func play(_ b64: String) {
        guard let data = Data(base64Encoded: b64), !data.isEmpty,
              let format = playFormat else { return }
        let frames = data.count / 2
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(frames)),
              let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let ints = raw.bindMemory(to: Int16.self)
            for i in 0..<frames { ch[0][i] = Float(Int16(littleEndian: ints[i])) / 32768 }
        }
        guard let toMix, let mixFormat,
              let out = Live.resampleBuffer(buf, with: toMix, to: mixFormat)
        else { return }
        if !player.isPlaying { player.play() }
        pending += 1
        player.scheduleBuffer(out, completionCallbackType: .dataPlayedBack) {
            [weak self] _ in
            Task { @MainActor in self?.drained() }
        }
    }

    /// One buffer of her own voice, as the speaker plays it. Runs on the
    /// audio thread, so it does the arithmetic here and hands the main actor
    /// one number.
    private nonisolated func heardSelf(_ buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData, buf.frameLength > 0 else { return }
        let n = Int(buf.frameLength)
        var sum: Float = 0
        for i in 0..<n { let x = ch[0][i]; sum += x * x }
        let rms = (sum / Float(n)).squareRoot()
        let dt = Float(Double(n) / max(buf.format.sampleRate, 1))
        Task { @MainActor in self.applyVoiceLevel(rms, dt) }
    }

    /// The expander. Instant attack on the running peak, slow release, and a
    /// floor at half of it -- speech bottoms out around there, so below it the
    /// mouth is shut rather than trembling on room tone.
    @MainActor
    private func applyVoiceLevel(_ rms: Float, _ dt: Float) {
        if rms > voicePeak {
            voicePeak = rms
        } else {
            voicePeak = max(Live.voicePeakFloor,
                            voicePeak * pow(Live.voicePeakDecay, dt))
        }
        let floor = voicePeak * Live.voiceFloorRatio
        let span = voicePeak - floor
        level = span > 0 ? max(0, min(1, (rms - floor) / span)) : 0
    }

    /// One buffer has actually left the speaker.
    private func drained() {
        pending = max(0, pending - 1)
        if pending == 0 {
            speaking = false
            // Not on `response.done`: that fires while seconds of her are
            // still queued here, and handing the floor back then lets the next
            // device start talking over the end of her own sentence.
            room?.giveFloor()
        }
    }

    /// Everything of hers still queued, thrown away mid-word.
    private func flush() {
        player.stop()
        pending = 0
        voicePeak = Live.voicePeakFloor
        level = 0
        player.play()
        speaking = false
        room?.giveFloor()
    }
}
