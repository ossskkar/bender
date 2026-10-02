import AVFoundation
import Observation
import Speech

/// 醒来 wakes her (Oscar, 2026-10-01). While no call is on and the app is in
/// front, the iPad listens for that one word with Apple's recogniser -- on the
/// device only: his data goes to Gemini or Anthropic and nowhere else, so on a
/// device that cannot recognise Mandarin locally this does not listen at all.
/// Nothing is paid for until she hears it; then the real call starts.
/// Observable so the screen can say why it is not listening: a listener that
/// silently does nothing looked exactly like one that did not hear him
/// (Oscar, 2026-10-02: "wake word should work when not in conversation").
@MainActor @Observable final class WakeListener {
    private(set) var problem: String?
    /// True while it is actually listening for the word.
    private(set) var listening = false
    @ObservationIgnored var onWake: () -> Void = {}

    @ObservationIgnored private let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    /// Made on first listen, not with the listener. ContentView holds this in
    /// @State, whose initial value is built again every time the app's body
    /// runs -- several times a second while she is on screen -- and each
    /// throwaway listener used to make and destroy an audio engine: the
    /// "stop / pause" pair in the log, 620 times in two minutes (16.0).
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var active = false
    /// Which request is current, so a stale callback cannot restart a new one.
    @ObservationIgnored private var generation = 0

    /// 醒来 and how the recogniser also writes what he says: xǐng lái comes
    /// back as 星来, 兴来 or 行来 often enough to miss him (2026-10-02).
    static let words = ["醒来", "醒來", "星来", "兴来", "行来"]

    func start() async {
        guard !active else { return }
        let allowed = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard allowed else { problem = "speech recognition is not allowed in Settings"; return }
        guard let recogniser, recogniser.supportsOnDeviceRecognition else {
            problem = "add Chinese (Mandarin) as a dictation language to wake her by voice"
            return
        }
        problem = nil
        active = true
        listen(recogniser)
    }

    func stop() {
        active = false
        listening = false
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
        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
        }
        engine.prepare()
        do { try engine.start() } catch {
            problem = "the microphone would not start"; active = false; listening = false; return
        }
        listening = true

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
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }
}

/// The sound of her arriving, timed to Singularity's flash at two seconds.
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
