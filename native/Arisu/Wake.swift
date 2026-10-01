import AVFoundation
import Speech

/// 醒来 wakes her (Oscar, 2026-10-01). While no call is on and the app is in
/// front, the iPad listens for that one word with Apple's recogniser -- on the
/// device only: his data goes to Gemini or Anthropic and nowhere else, so on a
/// device that cannot recognise Mandarin locally this does not listen at all.
/// Nothing is paid for until she hears it; then the real call starts.
@MainActor final class WakeListener {
    private(set) var problem: String?
    var onWake: () -> Void = {}

    private let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var active = false
    /// Which request is current, so a stale callback cannot restart a new one.
    private var generation = 0

    static let words = ["醒来", "醒來"]

    func start() async {
        guard !active else { return }
        let allowed = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard allowed else { problem = "Speech recognition is not allowed."; return }
        guard let recogniser, recogniser.supportsOnDeviceRecognition else {
            problem = "This iPad cannot recognise Mandarin on the device."
            return
        }
        active = true
        listen(recogniser)
    }

    func stop() {
        active = false
        teardown()
    }

    private func listen(_ recogniser: SFSpeechRecognizer) {
        generation += 1
        let mine = generation
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        try? s.setActive(true)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.contextualStrings = Self.words
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
        }
        engine.prepare()
        do { try engine.start() } catch { problem = "The microphone would not start."; active = false; return }

        task = recogniser.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let done = error != nil || result?.isFinal == true
            Task { @MainActor in
                guard let self, self.active, mine == self.generation else { return }
                if Self.words.contains(where: text.contains) {
                    self.stop()
                    self.onWake()
                } else if done {
                    self.teardown()
                    self.listen(recogniser)
                }
            }
        }
        // A request ends itself after about a minute; start a fresh one first.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard let self, self.active, mine == self.generation else { return }
            self.teardown()
            self.listen(recogniser)
        }
    }

    private func teardown() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }
}

/// The sound of her arriving, timed to Singularity's flash at one second.
/// Made by `sound/awaken.py`.
@MainActor enum Awaken {
    private static var player: AVAudioPlayer?

    static func play() {
        guard let url = Bundle.main.url(forResource: "awaken", withExtension: "wav") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 1
        player?.play()
    }
}
