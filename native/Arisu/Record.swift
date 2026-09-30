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

/// The panel above the deck (Oscar, 2026-09-30): a quarter of the screen,
/// wide and short, so the button sits left and the log runs right. Cyberpunk
/// on purpose -- neon on black, a grid, corner brackets, a ring that breathes
/// while it listens.
struct RecordPanel: View {
    /// Arisu lets go of the microphone while he dumps.
    var onStart: () -> Void = {}
    @StateObject private var rec = Recorder()
    @State private var showInsights = false
    @State private var pulse = false

    private let neon = Skin.mag
    private let wire = Skin.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    button
                    status
                    Spacer(minLength: 0)
                }
                .frame(width: 170)
                ScrollView {
                    if showInsights { insights } else { history }
                }
                .defaultScrollAnchor(showInsights ? .top : .bottom)
            }
        }
        .padding(14)
        .background(Grid(tint: wire))
        .overlay(Brackets(tint: neon))
        .padding(10)
        .task { await rec.load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("REC//BRAIN_DUMP")
                .font(Skin.mono(14, .bold)).tracking(2)
                .foregroundStyle(neon)
                .shadow(color: neon.opacity(0.9), radius: 6)
            Text(String(format: "%03d LOGS", rec.dumps.count))
                .font(Skin.mono(10)).foregroundStyle(wire.opacity(0.8))
            Spacer()
            tab("HISTORY", false)
            tab("INSIGHTS", true)
        }
    }

    private func tab(_ name: String, _ value: Bool) -> some View {
        let on = showInsights == value
        return Button { showInsights = value } label: {
            Text("[\(name)]")
                .font(Skin.mono(12, .semibold))
                .foregroundStyle(on ? wire : wire.opacity(0.45))
                .shadow(color: on ? wire : .clear, radius: 5)
        }
        .buttonStyle(.plain)
    }

    private var button: some View {
        let on = rec.started != nil
        let ink = on ? Skin.recording : neon
        return Button {
            if on { Task { await rec.finish() } } else { onStart(); rec.start() }
        } label: {
            ZStack {
                Circle().fill(ink.opacity(on ? 0.35 : 0.12))
                Circle().stroke(ink, lineWidth: 3)
                    .shadow(color: ink, radius: on && pulse ? 22 : 9)
                Circle().inset(by: -9)
                    .stroke(wire.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 7]))
                    .rotationEffect(.degrees(on && pulse ? 180 : 0))
                if rec.sending { ProgressView().tint(wire).scaleEffect(1.4) }
                else if let t = rec.started {
                    TimelineView(.periodic(from: t, by: 1)) { ctx in
                        let s = Int(ctx.date.timeIntervalSince(t))
                        Text(String(format: "%02d:%02d", s / 60, s % 60))
                            .font(Skin.mono(26, .bold)).foregroundStyle(.white)
                            .shadow(color: ink, radius: 6)
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "mic.fill").font(.system(size: 34))
                        Text("REC").font(Skin.mono(12, .bold)).tracking(3)
                    }
                    .foregroundStyle(neon)
                    .shadow(color: neon, radius: 6)
                }
            }
            .frame(width: 120, height: 120)
        }
        .buttonStyle(.plain)
        .disabled(rec.sending)
        .onChange(of: on) { _, now in
            if now {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            } else {
                withAnimation(.default) { pulse = false }
            }
        }
        .accessibilityLabel(on ? "Stop and save" : "Record a brain dump")
    }

    @ViewBuilder private var status: some View {
        if let p = rec.problem {
            Text("! " + p).font(Skin.mono(10)).foregroundStyle(Skin.recording)
                .multilineTextAlignment(.center)
            if let file = rec.pending {
                Button("[RETRY]") { Task { await rec.send(file) } }
                    .font(Skin.mono(11, .bold)).tint(wire)
            }
        } else {
            Text(rec.started != nil ? "> LISTENING_" : rec.sending ? "> DECODING_" : "> READY_")
                .font(Skin.mono(10)).foregroundStyle(wire.opacity(0.8))
        }
    }

    private func stamp(_ ms: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd // HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    private var history: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if rec.dumps.isEmpty {
                Text("> NO LOGS. PRESS REC AND TALK_")
                    .font(Skin.mono(11)).foregroundStyle(wire.opacity(0.7))
            }
            ForEach(rec.dumps) { d in
                HStack(spacing: 0) {
                    Rectangle().fill(neon).frame(width: 3).shadow(color: neon, radius: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stamp(d.ts)).font(Skin.mono(10)).foregroundStyle(neon)
                        Text(d.text).font(Skin.mono(13)).foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    Spacer(minLength: 0)
                }
                .background(wire.opacity(0.06))
                .overlay(Rectangle().stroke(wire.opacity(0.5), lineWidth: 1))
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
                Text(rec.insight.isEmpty ? "[ RUN ANALYSIS ]" : "[ REFRESH ]")
                    .font(Skin.mono(12, .bold)).foregroundStyle(wire)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(Rectangle().stroke(wire, lineWidth: 1))
                    .shadow(color: wire, radius: 4)
            }
            .buttonStyle(.plain).disabled(rec.thinking)
            if rec.thinking {
                Text("> PARSING LOGS_").font(Skin.mono(11)).foregroundStyle(neon)
            }
            Text(LocalizedStringKey(rec.insight))
                .font(Skin.mono(13)).foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A faint neon grid with scanlines, behind the panel.
private struct Grid: View {
    let tint: Color
    var body: some View {
        Canvas { ctx, size in
            var grid = Path()
            for x in stride(from: 0, through: size.width, by: 28) {
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 28) {
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(tint.opacity(0.07)), lineWidth: 1)
            for y in stride(from: 0, through: size.height, by: 3) {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(.black.opacity(0.25)))
            }
        }
        .background(Color.black)
    }
}

/// Neon corner brackets instead of a box.
private struct Brackets: View {
    let tint: Color
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, l: CGFloat = 22
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: w, y: h - l)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - l, y: h))
                p.move(to: CGPoint(x: l, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(tint, lineWidth: 2)
            .shadow(color: tint, radius: 5)
        }
        .allowsHitTesting(false)
    }
}
