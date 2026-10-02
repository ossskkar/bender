import SwiftUI
import Charts

// MARK: - At a glance (12.0)
//
// A panel beside her in voice mode with the day as lain has it: what is next
// on the plan, what is due, the running and the habits, the last two drawn as
// charts (Backlog, Arisu: "Her screen can show a panel next to her face" and
// "Answers about runs and habits come with a chart"). It is read from the
// same data.json as Singularity's rings, through `LainInfo`, and the iPad
// only ever reads it.

/// What the panel shows. Filled by `LainInfo.read`, which already works out
/// the plan, the due list and the race for the rings.
struct Glance {
    var loaded = false
    var plan: [String] = []
    var due: [String] = []
    var open = 0
    var raceDays: Int?
    /// Kilometres per week, the last eight, oldest first; the last one is this week.
    var weeks: [Week] = []
    var lastRun: String?
    var habits: [Habit] = []

    struct Week: Identifiable {
        let start: Date
        let km: Double
        var id: Date { start }
    }

    struct Habit: Identifiable {
        let id: String
        let name: String
        let icon: String
        /// Today, as "4/8" for a habit with a target, empty otherwise.
        let progress: String
        /// The last seven days, oldest first: true done, false missed, nil not due.
        let days: [Bool?]
    }

    mutating func read(_ d: [String: Any], now: Date, monday: Date) {
        let cal = Calendar.current

        // Running: eight weeks of totals, and the last run in words.
        let runs: [(Date, [String: Any])] = (d["days"] as? [String: Any] ?? [:]).compactMap { k, v in
            guard let date = LainInfo.parse(k) else { return nil }
            if let km = v as? Double { return (date, ["km": km]) }
            return (date, v as? [String: Any] ?? [:])
        }
        weeks = (0..<8).reversed().map { back in
            let start = cal.date(byAdding: .day, value: -7 * back, to: monday)!
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            let km = runs.filter { $0.0 >= start && $0.0 < end }
                .reduce(0.0) { $0 + (($1.1["km"] as? Double) ?? 0) }
            return Week(start: start, km: km)
        }
        if let (date, run) = runs.max(by: { $0.0 < $1.0 }), let km = run["km"] as? Double {
            var words = String(format: "%g KM", km) + " · " + LainInfo.short(LainInfo.iso(date))
            // `sp` is seconds per kilometre.
            if let sp = run["sp"] as? Double, sp > 0 {
                words += String(format: " · %d:%02d/KM", Int(sp) / 60, Int(sp) % 60)
            }
            lastRun = words
        }

        // Habits: today's progress and the week behind it.
        guard let h = d["habits"] as? [String: Any], let list = h["list"] as? [[String: Any]] else { return }
        let log = h["log"] as? [String: [String]] ?? [:]
        let counts = h["counts"] as? [String: [String: Int]] ?? [:]
        let today = cal.startOfDay(for: now)
        habits = list.map { item in
            let id = item["id"] as? String ?? ""
            let due = item["days"] as? [Int] ?? []
            let target = item["target"] as? Int ?? 0
            func done(_ key: String) -> Bool {
                (log[key] ?? []).contains(id) || (target > 0 && (counts[key]?[id] ?? 0) >= target)
            }
            let days: [Bool?] = (0..<7).reversed().map { back in
                let day = cal.date(byAdding: .day, value: -back, to: today)!
                guard due.contains(cal.component(.weekday, from: day) - 1) else { return nil }
                return done(LainInfo.iso(day))
            }
            let key = LainInfo.iso(today)
            let progress = target > 1 ? "\(done(key) ? target : counts[key]?[id] ?? 0)/\(target)" : ""
            return Habit(id: id, name: item["name"] as? String ?? "", icon: item["icon"] as? String ?? "",
                         progress: progress, days: days)
        }
    }
}

/// Which part of the panel the conversation is about, if any. Words only, so
/// she does not need to know the panel exists: he asks about his running, the
/// running chart comes up lit.
enum GlanceFocus: Equatable {
    case running, habits

    init?(_ line: String) {
        let t = line.lowercased()
        func has(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        if has(#"\b(run|runs|running|ran|km|kilomet|pace|race|marathon|training)"#) { self = .running }
        else if has(#"\b(habit|habits|vitamin|water|streak)"#) { self = .habits }
        else { return nil }
    }
}

struct GlancePanel: View {
    let glance: Glance
    var focus: GlanceFocus?
    var width: CGFloat = 320
    /// The plan and what is due on the left, the charts on the right: for a
    /// panel laid across the top of a wide pane, where one tall column would
    /// push the conversation off the screen (14.0).
    var columns = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Skin.caption("Today", Skin.mag)
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased())
                    .font(Skin.mono(11, .medium)).tracking(1.5).foregroundStyle(Skin.ink)
            }
            if !glance.loaded {
                Text("Reading lain…").font(Skin.mono(13)).foregroundStyle(Skin.off)
            } else if columns {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) { next; due }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 14) { charts }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                next
                charts
                due
            }
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .plate { Rectangle().fill(Color.black.opacity(0.62)) }
        .edge { Rectangle().stroke(Skin.cyan.opacity(0.45), lineWidth: 1) }
        .animation(.easeInOut(duration: 0.3), value: focus)
    }

    private var next: some View {
        section("Next", glance.plan, empty: "Nothing left on the plan").tourSpot("glanceToday")
    }

    private var due: some View {
        section("Due", glance.due, empty: "Nothing due · \(glance.open) open")
    }

    @ViewBuilder private var charts: some View {
        running.tourSpot("glanceRunning")
        habits.tourSpot("glanceHabits")
    }

    private func section(_ title: String, _ lines: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Skin.caption(title, Skin.cyan)
            ForEach(lines.isEmpty ? [empty.uppercased()] : lines, id: \.self) { line in
                Text(line).font(Skin.mono(13)).foregroundStyle(lines.isEmpty ? Skin.off : .white)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }

    /// The part being talked about wears a lit edge, as a pressed key does.
    private func lit(_ on: Bool) -> some View {
        Rectangle().stroke(Skin.mag.opacity(on ? 0.9 : 0), lineWidth: 1.5)
            .shadow(color: on ? Skin.mag : .clear, radius: 6)
            .padding(-6)
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Skin.caption("Running", Skin.cyan)
                Spacer()
                if let days = glance.raceDays {
                    Text("\(days) DAYS TO THE RACE").font(Skin.mono(11, .semibold)).foregroundStyle(Skin.mag)
                }
            }
            // Eight weeks, this one lit: whether the training is building is
            // the question, and one week alone cannot answer it.
            Chart(glance.weeks) { w in
                BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("km", w.km))
                    .foregroundStyle(w.id == glance.weeks.last?.id ? Skin.cyan : Skin.cyan.opacity(0.4))
                    .annotation(position: .top) {
                        if w.km > 0 {
                            Text(String(format: "%.0f", w.km)).font(Skin.mono(9)).foregroundStyle(Skin.ink)
                        }
                    }
            }
            .chartXAxis {
                AxisMarks(values: glance.weeks.map(\.start)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits)).font(Skin.mono(8))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 92)
            Text("LAST RUN · " + (glance.lastRun ?? "NONE")).font(Skin.mono(12)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .overlay(lit(focus == .running))
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Skin.caption("Habits", Skin.cyan)
                Spacer()
                Text("LAST 7 DAYS").font(Skin.mono(9, .medium)).tracking(1).foregroundStyle(Skin.ink)
            }
            ForEach(glance.habits) { h in
                HStack(spacing: 6) {
                    Text(h.icon).font(.system(size: 13))
                    // Two lines rather than an ellipsis: in portrait the panel
                    // is 266pt and "Wake Up by 9:00" lost its time (13.0).
                    Text(h.name).font(Skin.mono(12)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    if !h.progress.isEmpty {
                        Text(h.progress).font(Skin.mono(11, .semibold)).foregroundStyle(Skin.cyan)
                            .fixedSize()
                    }
                    // Today is the last square.
                    HStack(spacing: 3) {
                        ForEach(Array(h.days.enumerated()), id: \.offset) { _, done in
                            Rectangle()
                                .fill(done == true ? Skin.good : done == false ? Skin.raised : .clear)
                                .overlay(Rectangle().stroke(done == nil ? .clear : Skin.good.opacity(0.4)))
                                .frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
        .overlay(lit(focus == .habits))
    }
}
