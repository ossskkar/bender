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
    @Published private(set) var speaking = false      // she is talking
    @Published private(set) var hearing = false       // he is talking
    /// A tool is out. On this path that means `think` -- a whole turn of
    /// Hermes on architect, which is seconds rather than milliseconds, so it
    /// is the one wait long enough that the screen has to account for it.
    @Published private(set) var thinking = false
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
        halted.withLock { $0 = false }
        guard socket == nil else { return }
        Task { await connect() }
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
            let token = try await brain.realtimeToken(model: model)
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
        player.stop()
        pending = 0
        status = "idle"
    }

    /// Off, not asleep: the socket goes, the tap comes down and the engine
    /// stops, so nothing is recorded, nothing is streamed and nothing is
    /// billed. `begin()` builds all of it back.
    func end() {
        stopped = true
        halted.withLock { $0 = true }
        dormant = false
        speaking = false
        hearing = false
        thinking = false
        level = 0
        player.stop()
        pending = 0
        idleTimer?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        engine.inputNode.removeTap(onBus: 0)
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
            Task { await self.runTool(name: name, callID: callID, args: args) }

        case "error":
            let err = ev["error"] as? [String: Any]
            status = (err?["message"] as? String) ?? "error"

        default:
            break
        }
    }

    // MARK: - her hands, which are on the desk

    private func runTool(name: String, callID: String, args: String) async {
        var output = "{\"ok\":true}"
        let isBody = name == "set_mood"
        if !isBody { thinking = true }
        defer { if !isBody { thinking = false } }
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
        send(item)
        // `set_mood` is her face, not an answer. Asking for a response after it
        // made her reply twice to one question: once for the mood call and once
        // for the thinking call, because she routinely makes both in a turn.
        // Only the tool that actually fetched something gets a new response.
        if !isBody { send(["type": "response.create"]) }
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
            self.level = min(1, rms * 12)
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

    /// One buffer has actually left the speaker.
    private func drained() {
        pending = max(0, pending - 1)
        if pending == 0 { speaking = false }
    }

    /// Everything of hers still queued, thrown away mid-word.
    private func flush() {
        player.stop()
        pending = 0
        player.play()
        speaking = false
    }
}
