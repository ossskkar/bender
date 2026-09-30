import AVFoundation
import SwiftUI

/// Brain dumps: one big button, talk, press again (Oscar, 2026-09-30).
///
/// The iPad records 16k mono WAV and ships it to lain's `POST /dumps`, where
/// architect's own whisper-server transcribes it -- the audio never leaves his
/// machines. History and insights come back from the same place; insights are
/// Gemini through lain's `llm.ask`, which is where his data is allowed to go.
@MainActor final class Recorder: ObservableObject {
    struct Dump: Codable, Identifiable { let id: String; let ts: Double; let text: String }

    @Published var dumps: [Dump] = []
    @Published var started: Date?
    @Published var sending = false
    @Published var insight = ""
    @Published var thinking = false
    @Published var problem: String?
    /// A recording the desk did not take. Kept on disk until it does, so a
    /// dropped connection never costs him the thought.
    @Published var pending: URL?

    static let base = URL(string: "https://architect-server.tailaa64e9.ts.net:8443/")!
    private var rec: AVAudioRecorder?
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300   // whisper on architect runs about real time
        return URLSession(configuration: c)
    }()

    func load() async {
        struct Answer: Decodable { let dumps: [Dump] }
        guard let (data, _) = try? await session.data(from: Self.base.appendingPathComponent("dumps")),
              let got = try? JSONDecoder().decode(Answer.self, from: data) else { return }
        dumps = got.dumps
    }

    func start() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? s.setActive(true)
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dump-\(Int(Date().timeIntervalSince1970)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        guard let r = try? AVAudioRecorder(url: file, settings: settings), r.record() else {
            problem = "The microphone would not start."
            return
        }
        rec = r
        problem = nil
        started = Date()
    }

    func finish() async {
        guard let r = rec else { return }
        r.stop()
        rec = nil
        started = nil
        await send(r.url)
    }

    func send(_ file: URL) async {
        guard let wav = try? Data(contentsOf: file) else { return }
        sending = true
        defer { sending = false }
        var req = URLRequest(url: Self.base.appendingPathComponent("dumps"))
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        req.httpBody = wav
        guard let (data, resp) = try? await session.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode else {
            pending = file
            problem = "The desk did not answer. The recording is kept."
            return
        }
        if code == 422 {               // silence: nothing worth keeping
            try? FileManager.default.removeItem(at: file)
            pending = nil
            problem = "Nothing was heard."
            return
        }
        guard code == 200, let row = try? JSONDecoder().decode(Dump.self, from: data) else {
            pending = file
            problem = "The desk refused it (\(code)). The recording is kept."
            return
        }
        try? FileManager.default.removeItem(at: file)
        pending = nil
        problem = nil
        dumps.append(row)
    }

    func remove(_ d: Dump) async {
        var req = URLRequest(url: Self.base.appendingPathComponent("dumps/remove"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": d.id])
        if (try? await session.data(for: req)) != nil { dumps.removeAll { $0.id == d.id } }
    }

    func think() async {
        struct Answer: Decodable { let text: String?; let error: String? }
        thinking = true
        defer { thinking = false }
        guard let (data, _) = try? await session.data(
                from: Self.base.appendingPathComponent("dumps/insights")),
              let got = try? JSONDecoder().decode(Answer.self, from: data) else {
            insight = "The desk did not answer."
            return
        }
        insight = got.text ?? got.error ?? ""
    }
}

/// The panel beside the deck: history or insights on top, the button at the
/// bottom where his thumb is, like the deck's keys.
struct RecordPanel: View {
    /// Arisu lets go of the microphone while he dumps.
    var onStart: () -> Void = {}
    @StateObject private var rec = Recorder()
    @State private var showInsights = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Skin.caption("record", Skin.mag.opacity(0.85))
                Spacer()
                Picker("", selection: $showInsights) {
                    Text("history").tag(false)
                    Text("insights").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 170)
            }
            .padding(.top, 14)

            ScrollView {
                if showInsights { insights } else { history }
            }
            .defaultScrollAnchor(showInsights ? .top : .bottom)

            if let p = rec.problem {
                HStack {
                    Text(p).font(Skin.mono(11)).foregroundStyle(Skin.recording)
                    Spacer()
                    if let file = rec.pending {
                        Button("Retry") { Task { await rec.send(file) } }
                            .font(Skin.mono(12, .semibold)).tint(Skin.cyan)
                    }
                }
            }
            button.frame(maxWidth: .infinity).padding(.bottom, 18)
        }
        .padding(.horizontal, 12)
        .task { await rec.load() }
    }

    private var button: some View {
        let on = rec.started != nil
        return Button {
            if on { Task { await rec.finish() } } else { onStart(); rec.start() }
        } label: {
            ZStack {
                Circle().fill(on ? Skin.recording : Skin.recording.opacity(0.18))
                Circle().stroke(Skin.recording, lineWidth: 3)
                if rec.sending { ProgressView().tint(.white).scaleEffect(1.4) }
                else if let t = rec.started {
                    TimelineView(.periodic(from: t, by: 1)) { ctx in
                        let s = Int(ctx.date.timeIntervalSince(t))
                        Text(String(format: "%d:%02d", s / 60, s % 60))
                            .font(Skin.mono(26, .semibold)).foregroundStyle(.white)
                    }
                } else {
                    Image(systemName: "mic.fill").font(.system(size: 44)).foregroundStyle(.white)
                }
            }
            .frame(width: 150, height: 150)
        }
        .buttonStyle(.plain)
        .disabled(rec.sending)
        .accessibilityLabel(on ? "Stop and save" : "Record a brain dump")
    }

    private var history: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if rec.dumps.isEmpty {
                Text("Nothing yet. Press the button and talk.")
                    .font(Skin.mono(12)).foregroundStyle(Skin.ink)
            }
            ForEach(rec.dumps) { d in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date(timeIntervalSince1970: d.ts / 1000),
                         format: .dateTime.weekday().day().month().hour().minute())
                        .font(Skin.mono(10)).foregroundStyle(Skin.ink)
                    Text(d.text).font(.system(size: 14)).foregroundStyle(.white)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .raised(Skin.cyan, stroke: 0.6)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await rec.remove(d) }
                    }
                }
            }
        }
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await rec.think() }
            } label: {
                Label(rec.insight.isEmpty ? "Read my dumps" : "Refresh", systemImage: "sparkles")
                    .font(Skin.mono(13, .semibold))
            }
            .tint(Skin.cyan).disabled(rec.thinking)
            if rec.thinking { ProgressView().tint(Skin.cyan) }
            Text(LocalizedStringKey(rec.insight))
                .font(.system(size: 14)).foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
