import AVFoundation

/// Her voice, made on the phone.
///
/// The web version fetched AAC from the Mac because iOS `speechSynthesis`
/// silently refuses to speak in a pinned page. That cost 3-6 seconds per reply,
/// almost all of it `say` starting up AudioToolbox on the desk. AVSpeechSynthesizer
/// is already resident here, so the same sentence starts in about a fifth of a
/// second and the round trip loses its largest single piece.
final class Voice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false

    /// Raised while she talks so the ear ignores the room, and lowered on the
    /// real `didFinish` -- the event the browser never reliably gave us.
    var onSpeakingChanged: ((Bool) -> Void)?

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Cut her off mid-word. `didCancel` fires, which lowers `speaking` and
    /// re-opens the ear -- the same path a finished sentence takes.
    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func say(_ text: String) {
        guard !text.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        // Low and flat: she is a machine, not an assistant.
        u.rate = 0.52
        u.pitchMultiplier = 0.72
        u.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-GB.Daniel")
            ?? AVSpeechSynthesisVoice(language: "en-GB")
        synth.speak(u)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        speaking = true; onSpeakingChanged?(true)
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        speaking = false; onSpeakingChanged?(false)
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        speaking = false; onSpeakingChanged?(false)
    }
}
