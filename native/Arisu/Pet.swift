import Foundation
import SwiftUI

/// Everything joined up: the ear hands an utterance to the desk, the desk hands
/// back a line, the voice says it. One object so the view has one thing to watch.
@MainActor
final class Pet: ObservableObject {
    @Published var line = ""
    @Published var heard = ""
    @Published var mood = "calm"
    @Published var action = "idle"
    @Published var thinking = false
    @Published var level: Float = 0
    /// Whether she is in the conversation at all. False is not a mute: the
    /// microphone tap comes down and the socket goes, so nothing is heard,
    /// nothing is recorded and nothing is billed while it is off.
    @Published private(set) var running = true

    /// Which path is running. Mutually exclusive -- all three want the
    /// microphone and the audio session -- and cycled from the button under
    /// her, because the only way to judge these against each other is to hear
    /// them one after another in the same room.
    enum Mode: String, CaseIterable {
        case mini, full, whisper

        /// What the button says.
        var label: String {
            switch self {
            case .mini:    return "mini"
            case .full:    return "full"
            case .whisper: return "whisper"
            }
        }

        /// $10/$20 per million audio tokens against $32/$64 -- the same voice
        /// on a model 3.2x the price. Whisper spends nothing at OpenAI.
        var model: String? {
            switch self {
            case .mini:    return "gpt-realtime-2.1-mini"
            case .full:    return "gpt-realtime-2.1"
            case .whisper: return nil
            }
        }
    }
    @Published var mode: Mode = .mini

    let ear = Ear()
    let live = Live()
    let voice = Voice()
    private let brain = Brain()
    private var seen = -1
    private var levelSink: Task<Void, Never>?
    private var turn: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var resend: Task<Void, Never>?
    /// A finished line she has not been allowed to say yet, because he was
    /// still talking when it arrived.
    private var held: String?
    private var heIsTalking = false
    private var lastWav: Data?

    init() {
        voice.onSpeakingChanged = { [weak self] talking in
            self?.ear.herVoice = talking
        }
        ear.onBargeIn = { [weak self] in
            Task { @MainActor in self?.cutIn() }
        }
        ear.onUtterance = { [weak self] wav, amend in
            Task { @MainActor in self?.take(wav, amend: amend) }
        }
        ear.onCapture = { [weak self] talking, shipped in
            Task { @MainActor in self?.capture(talking, shipped: shipped) }
        }
        levelSink = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    self.level = !self.running ? 0
                        : (self.mode == .whisper ? self.ear.level : self.live.level)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    func begin() {
        running = true
        mode == .whisper ? beginWhisper() : beginLive()
    }

    /// The stop button. Whichever path owns the microphone, it lets go of it
    /// -- the two are mutually exclusive but only one is up at a time, and
    /// stopping the wrong one silently leaves the other listening.
    func toggleRunning() {
        running ? halt() : begin()
    }

    private func halt() {
        running = false
        voice.stop()
        turn?.cancel(); turn = nil
        resend?.cancel(); resend = nil
        watcher?.cancel(); watcher = nil
        held = nil
        heIsTalking = false
        thinking = false
        level = 0
        live.end()
        ear.stop()
    }

    /// Speech to speech. Nothing here decides when he has stopped talking or
    /// whether he is interrupting: the model does both, which is the whole
    /// reason this path exists.
    private func beginLive() {
        live.onMood = { [weak self] m, a in
            Task { @MainActor in self?.mood = m; self?.action = a }
        }
        live.onTranscript = { [weak self] t in
            Task { @MainActor in self?.line = t }
        }
        live.onHeard = { [weak self] t in
            Task { @MainActor in self?.heard = t }
        }
        live.model = mode.model ?? "gpt-realtime-2.1-mini"
        live.begin()
    }

    private func beginWhisper() {
        do { try ear.start() }
        catch { line = "No ear. Check the microphone permission." }
        if watcher == nil { watcher = Task { await self.watch() } }
    }

    /// mini -> full -> whisper -> mini. Switching between the two realtime
    /// models is only a reconnection; crossing to or from whisper swaps which
    /// machinery owns the microphone.
    func cycleMode() {
        let all = Mode.allCases
        let next = all[(all.firstIndex(of: mode)! + 1) % all.count]
        let wasLive = mode != .whisper
        mode = next
        line = next.label
        heard = ""

        if next == .whisper {
            live.end()
            beginWhisper()
            return
        }
        if wasLive {
            live.use(model: next.model!)     // same path, different model
            return
        }
        ear.stop()
        voice.stop()
        watcher?.cancel(); watcher = nil
        turn?.cancel(); turn = nil
        beginLive()
    }

    /// He has started talking over her. She stops mid-word the way a person
    /// does, and the answer she was still working on is abandoned -- he is
    /// already replacing the question.
    private func cutIn() {
        voice.stop()
        turn?.cancel()
        turn = nil
        thinking = false
    }

    /// A finished utterance. Whatever was in flight is dropped: he has said
    /// something newer, and the desk will discard the older turn too.
    private func take(_ wav: Data, amend: Bool) {
        turn?.cancel()
        resend?.cancel()
        held = nil
        if amend { voice.stop() }
        lastWav = wav
        turn = Task { await self.send(wav) }
    }

    /// He has started or stopped talking. While he is talking she says
    /// nothing -- a line that arrives mid-sentence waits, and is dropped
    /// outright if what he goes on to say replaces the question.
    private func capture(_ talking: Bool, shipped: Bool) {
        heIsTalking = talking
        if talking {
            resend?.cancel()
            return
        }
        // He stopped without saying enough to send -- a cough, a chair. There
        // is no newer question coming, so anything held can be said now.
        if !shipped, let h = held {
            held = nil
            if running { voice.say(h) }
        }
    }

    /// Held open against the desk so that anything she decides to say arrives
    /// the moment it exists: the aside while a tool runs, and the remarks she
    /// makes on her own timer. Without it the aside would have nowhere to go
    /// -- the phone is already waiting on the request that produces it.
    private func watch() async {
        // Start from where she is, so the line already on screen is not
        // replayed the instant the app opens.
        if let now = try? await brain.state() { seen = max(seen, now.seq) }
        while !Task.isCancelled {
            do {
                let snap = try await brain.state(since: seen)
                apply(snap)
            } catch {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func send(_ wav: Data, force: Bool = false) async {
        thinking = true
        defer { thinking = false }
        do {
            let snap = try await brain.listen(wav, force: force)
            // He cut in, or said something newer, while this was in flight.
            // The answer is to a question he has already withdrawn.
            if Task.isCancelled { return }
            if snap.incomplete == true {
                // The desk heard a sentence that stops rather than ends, and
                // deliberately did not answer it. Wait for the rest of it. If
                // it never comes, ask again and make her answer what there is.
                heard = snap.heard ?? ""
                resend?.cancel()
                resend = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled, let self, let w = self.lastWav
                    else { return }
                    await self.send(w, force: true)
                }
                return
            }
            if snap.ignored == true {
                heard = snap.heard ?? ""      // the room, shown faintly
                return
            }
            apply(snap)
        } catch {
            // Cancelling the request is not a failure, and must not be
            // reported as one -- it is him changing his mind.
            if !Task.isCancelled { heard = "desk unreachable" }
        }
    }

    private func apply(_ s: Snap) {
        // Paused is silent. A snapshot can land in the gap between the button
        // and the watcher noticing it was cancelled, and there is no version of
        // "she is not listening" in which she still answers.
        guard running else { return }
        guard s.seq != seen, !s.line.isEmpty else { return }
        seen = s.seq
        line = s.line
        heard = s.heard ?? ""
        mood = s.mood
        action = s.action
        if heIsTalking {
            held = s.line       // shown on screen, but not said over him
            return
        }
        voice.say(s.line)
    }
}
