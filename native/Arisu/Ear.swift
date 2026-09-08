import AVFoundation
import Foundation

/// The microphone, and the decision about when Oscar has finished a sentence.
///
/// The browser version of this was the whole problem. Safari lends the mic to
/// one consumer, suspends the AudioContext when it feels like it, runs the
/// sample loop on the main thread, and hands over audio at about -43 dBFS --
/// quiet enough that whisper dropped her name off the front of every sentence.
/// AVAudioEngine has none of those properties: the tap runs on its own thread,
/// the session survives backgrounding, and `.voiceChat` turns on the system
/// echo canceller so she stops hearing herself.
final class Ear: ObservableObject {
    @Published var level: Float = 0        // 0...1, for the meter
    @Published var listening = false

    /// One finished utterance, already 16k mono and gain-corrected. `amend`
    /// means it carries the previous utterance too, because he carried on
    /// talking straight after it was sent -- the turn should be replaced
    /// rather than added to.
    var onUtterance: ((Data, Bool) -> Void)?

    /// He has started talking over her. Fired before any audio is shipped,
    /// so she can stop mid-word while he is still in his first syllable.
    var onBargeIn: (() -> Void)?

    /// Whether he is mid-utterance, and on the closing call whether anything
    /// was actually sent. She uses this to keep quiet while he is talking --
    /// answering over the top of him was most of what "it cuts me off" meant.
    var onCapture: ((Bool, Bool) -> Void)?

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 16_000

    // The same shape of gate the web version ended up with, which was arrived
    // at by measurement: ride the room's own noise floor rather than a fixed
    // threshold, so a loud room raises the bar instead of triggering all night.
    private var floor: Float = 0
    private var speaking = false
    private var buffer: [Float] = []
    private var preRoll: [Float] = []
    private var quietSince: Date?
    private var startedAt: Date?
    private var lastLoud: Date?
    /// How much of `buffer` was in it the last time he was audible. Everything
    /// after this is the hang -- silence he is waiting through, and which
    /// whisper would otherwise be paid to transcribe.
    private var loudMark = 0

    // 1.2s was the first guess and it is most of what "slow to notice you"
    // meant: the phone sits mute for that long after the last word before it
    // sends anything. 0.65 felt right on short commands and then failed on
    // real speech -- he pauses to think mid-sentence, the clip ships, and by
    // the time he resumes she is already talking, which raises the gate on
    // him and turns the rest of his thought into a barge-in. The amend window
    // cannot rescue that. 1.1 is the pause he actually takes.
    private let hang: TimeInterval = 1.1   // quiet that ends an utterance
    // A short burst is usually the beginning of a thought rather than the end
    // of one, so it is given longer to continue before being sent.
    private let openingHang: TimeInterval = 1.4
    private let shortUtterance: TimeInterval = 0.8
    private let minUtterance: TimeInterval = 0.4
    private let maxUtterance: TimeInterval = 15
    private let preRollSeconds = 0.45

    /// Set while she talks. She is no longer simply ignored: the ear stays
    /// open so he can cut her off, but the bar is raised and he has to hold
    /// it, or the echo canceller's leftovers interrupt her on his behalf.
    var herVoice = false {
        didSet { if herVoice != oldValue { herVoiceSince = Date(); loudRun = nil } }
    }
    private var herVoiceSince: Date?
    private var loudRun: Date?
    private let bargeStrictness: Float = 2.2
    private let bargeHold: TimeInterval = 0.18   // long enough to not be a cough
    private let bargeGrace: TimeInterval = 0.35  // let the canceller settle first

    /// The clip last sent, kept only long enough to glue a continuation onto.
    private var pending: [Float] = []
    private var sentAt: Date?
    // Long enough to cover drawing breath mid-thought. It can afford to be:
    // a continuation costs nothing now, because the desk throws away the
    // turn it replaces and she has not spoken over him in the meantime.
    private let amendWindow: TimeInterval = 2.5

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .voiceChat gives echo cancellation; .duckOthers keeps her audible.
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: sampleRate,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else { throw NSError(domain: "Ear", code: 1) }

        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buf, _ in
            guard let self else { return }
            guard let out = self.convert(buf, with: converter, to: outFormat) else { return }
            self.feed(out)
        }

        engine.prepare()
        try engine.start()
        DispatchQueue.main.async { self.listening = true }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        DispatchQueue.main.async { self.listening = false }
    }

    private func convert(_ buf: AVAudioPCMBuffer,
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
}

// MARK: - the gate

extension Ear {
    /// One block of 16k mono samples. Decides whether Oscar is talking, and
    /// when he has stopped, hands the whole utterance over.
    func feed(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }

        var sum: Float = 0
        for x in chunk { sum += x * x }
        let rms = (sum / Float(chunk.count)).squareRoot()

        DispatchQueue.main.async { self.level = min(1, rms * 12) }

        let now = Date()
        // Her own voice must not drag the room's floor up with it, or the bar
        // is still high for a second after she stops.
        if !herVoice {
            floor = floor == 0 ? rms : floor * 0.995 + rms * 0.005
        }
        // Native input is far hotter than Safari's, so the absolute minimum
        // that had to be 0.002 in the browser can sit where it belongs.
        let gate = max(0.006, floor * 2.6)

        if herVoice {
            // Listening through her own sentence. Keep the pre-roll running so
            // that when he does cut in, the word he cut in with survives.
            speaking = false; buffer = []; loudMark = 0
            preRoll.append(contentsOf: chunk)
            let keep = Int(preRollSeconds * sampleRate)
            if preRoll.count > keep { preRoll.removeFirst(preRoll.count - keep) }

            let settled = now.timeIntervalSince(herVoiceSince ?? now) > bargeGrace
            if settled && rms > gate * bargeStrictness {
                if loudRun == nil { loudRun = now }
                if now.timeIntervalSince(loudRun ?? now) >= bargeHold {
                    loudRun = nil
                    onBargeIn?()
                }
            } else {
                loudRun = nil
            }
            return
        }
        loudRun = nil

        let loud = rms > gate

        if !speaking {
            preRoll.append(contentsOf: chunk)
            let keep = Int(preRollSeconds * sampleRate)
            if preRoll.count > keep { preRoll.removeFirst(preRoll.count - keep) }
            if loud {
                speaking = true
                startedAt = now; lastLoud = now; quietSince = nil
                buffer = preRoll
                loudMark = buffer.count
                onCapture?(true, false)
            }
            return
        }

        buffer.append(contentsOf: chunk)
        if loud { lastLoud = now; quietSince = nil; loudMark = buffer.count }
        else if quietSince == nil { quietSince = now }

        let spokenSoFar = (lastLoud ?? now).timeIntervalSince(startedAt ?? now)
        let need = spokenSoFar < shortUtterance ? openingHang : hang
        let ranLong = now.timeIntervalSince(startedAt ?? now) > maxUtterance
        let wentQuiet = quietSince.map { now.timeIntervalSince($0) > need } ?? false
        guard ranLong || wentQuiet else { return }

        // Ship what he said plus a short tail, not the hang as well: the
        // silence carries no words and whisper is paid by the second.
        let tail = Int(0.25 * sampleRate)
        var clip = Array(buffer.prefix(min(buffer.count, loudMark + tail)))

        // If he began again within a moment of the last clip being sent, the
        // endpoint was simply wrong -- he was drawing breath, not finishing.
        // Glue the two together and let the turn be replaced rather than
        // leaving half a sentence on the desk and answering it.
        var amend = false
        if let sent = sentAt, let began = startedAt,
           began.timeIntervalSince(sent) < amendWindow, !pending.isEmpty {
            // No silence is inserted between the two halves: the first clip
            // already carries a 0.25s tail and the second opens with 0.45s of
            // pre-roll, which is the pause itself. Padding it further reads to
            // whisper as a sentence boundary, which is the opposite of what
            // this is for.
            clip = pending + clip
            let cap = Int(maxUtterance * sampleRate)
            if clip.count > cap { clip.removeFirst(clip.count - cap) }
            amend = true
        }
        // Time actually spent making noise, not the length of the clip -- the
        // clip always carries the trailing silence, and measuring that instead
        // lets every cough through as a second of "speech".
        let spoke = (lastLoud ?? now).timeIntervalSince(startedAt ?? now)
        speaking = false; buffer = []; preRoll = []; quietSince = nil
        loudMark = 0

        guard spoke >= minUtterance else {
            onCapture?(false, false)      // a cough; nothing is coming
            return
        }
        pending = clip
        sentAt = now
        onUtterance?(Ear.wav16(normalise(clip)), amend)
        onCapture?(false, true)
    }

    /// Lift the clip to a normal speaking level. Whisper transcribes level,
    /// not effort: at the phone's own -43 dBFS it silently dropped her name
    /// off the front of every sentence.
    private func normalise(_ pcm: [Float]) -> [Float] {
        var peak: Float = 0
        for x in pcm { peak = max(peak, abs(x)) }
        let gain = min(24, 0.55 / max(peak, 0.0025))
        return gain > 1.2 ? pcm.map { $0 * gain } : pcm
    }

    /// 16-bit mono WAV, which is what the desk's whisper wants.
    static func wav16(_ pcm: [Float], rate: Int = 16_000) -> Data {
        var d = Data(capacity: 44 + pcm.count * 2)
        func str(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + pcm.count * 2)); str("WAVEfmt ")
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(pcm.count * 2))
        for x in pcm {
            let c = max(-1, min(1, x))
            u16(UInt16(bitPattern: Int16(c < 0 ? c * 32768 : c * 32767)))
        }
        return d
    }
}
