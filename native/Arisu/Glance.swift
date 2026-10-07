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
struct Glance: Equatable {
    var loaded = false
    var plan: [String] = []
    var due: [String] = []
    var open = 0
    var raceDays: Int?
    /// Kilometres per week, the last eight, oldest first; the last one is this week.
    var weeks: [Week] = []
    var lastRun: String?
    var habits: [Habit] = []
    /// This week of the 14-week plan, while the plan runs (25.0).
    var training: Training?
    /// What 100 km would take at his current running, while the plan runs (25.0).
    var pace: RacePace?

    struct Week: Identifiable, Equatable {
        let start: Date
        let km: Double
        /// The plan's kilometres for this week; nil outside the plan (25.0).
        var planned: Double? = nil
        var id: Date { start }
    }

    /// Project 100K's 14-week plan, as `p100k.py` (PLAN, copied from the old
    /// app.html) has it: phase, planned km, long run km. Week 1 is the Monday
    /// of race week minus 13 weeks, so moving the race moves the plan. The
    /// last week's long run is the race itself.
    static let planTable: [(phase: String, km: Double, long: Double)] = [
        ("Rebuild", 30, 15), ("Rebuild", 36, 18), ("Rebuild", 42, 24),
        ("Cutback", 30, 16), ("Ultra block", 48, 28), ("Ultra block", 54, 32),
        ("Cutback", 38, 20), ("Ultra block", 58, 36), ("Ultra block", 62, 40),
        ("Cutback", 44, 24), ("Peak", 68, 58), ("Recover", 46, 26),
        ("Taper", 32, 18), ("RACE", 111, 100),
    ]
    static var raceKm: Double { planTable.last!.long }

    /// The day he stopped Project 100K ("I'm not gonna do the 100 kilometer
    /// project", Oscar, 2026-10-01), as lain's server/p100k.py DROPPED has it.
    /// While it is set the iPad knows no race: no countdown, no plan week, no
    /// race pace, no planned bars, and the ring says the week's kilometres
    /// only. The runs themselves still show. nil brings it all back.
    /// checks/race-plan.py fails if this and lain's drift.
    static let dropped: String? = "2026-10-01"

    /// The race day from data.json's settings, or nil when there is no race
    /// to speak of (26.0). The one place both the panel and the ring ask.
    static func raceDay(_ d: [String: Any]) -> Date? {
        guard dropped == nil, let s = (d["settings"] as? [String: Any])?["raceDate"] as? String else { return nil }
        return LainInfo.parse(s)
    }

    struct Training: Equatable {
        /// 1 to 14.
        let week: Int
        let phase: String
        let planned: Double
        let longRun: Double
        /// Run so far this week, and the longest single run in it.
        let run: Double
        let longest: Double
    }

    /// A finish time for the race from one run he has done, by Riegel's
    /// formula (time grows as distance to the power 1.06), the common way to
    /// carry a time from one distance to another. An estimate, and said to be
    /// one: past the marathon it tends to promise too much.
    struct RacePace: Equatable {
        /// Seconds for the whole race, and per kilometre at an even pace.
        let finish: Double
        let perKm: Double
        /// The run it comes from, as "16 KM · 30 AUG".
        let from: String

        static func riegel(km: Double, secPerKm: Double, to distance: Double) -> Double {
            km * secPerKm * pow(distance / km, 1.06)
        }
    }

    /// "13:32" for a time of hours and minutes, "8:07" for a pace.
    static func clock(_ s: Double) -> String {
        let m = Int(s.rounded()) / 60
        return String(format: "%d:%02d", m / 60, m % 60)
    }
    static func perKm(_ s: Double) -> String {
        let r = Int(s.rounded())
        return String(format: "%d:%02d", r / 60, r % 60)
    }

    struct Habit: Identifiable, Equatable {
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
        // The plan's week 1, from the race date: the Monday of race week,
        // minus 13 weeks, as p100k.py works it out.
        var planStart: Date?
        var raceDay: Date?
        if let race = Self.raceDay(d) {
            let back = (cal.component(.weekday, from: race) + 5) % 7      // days since Monday
            planStart = cal.date(byAdding: .day, value: -back - 7 * 13, to: race)
            raceDay = race
        }
        func planWeek(_ start: Date) -> Int? {
            guard let planStart, let days = cal.dateComponents([.day], from: planStart, to: start).day,
                  days >= 0, days / 7 < Self.planTable.count else { return nil }
            return days / 7
        }
        weeks = (0..<8).reversed().map { back in
            let start = cal.date(byAdding: .day, value: -7 * back, to: monday)!
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            let km = runs.filter { $0.0 >= start && $0.0 < end }
                .reduce(0.0) { $0 + (($1.1["km"] as? Double) ?? 0) }
            return Week(start: start, km: km, planned: planWeek(start).map { Self.planTable[$0].km })
        }
        // This week of the plan, from week 1 to race day and not after it:
        // the question every day of the plan is "am I on it" (Backlog, Arisu:
        // "Arisu gets me through race week").
        if let raceDay, let w = planWeek(monday), cal.startOfDay(for: now) <= raceDay {
            let row = Self.planTable[w]
            let mine = runs.filter { $0.0 >= monday }.map { ($0.1["km"] as? Double) ?? 0 }
            training = Training(week: w + 1, phase: row.phase, planned: row.km, longRun: row.long,
                                run: mine.reduce(0, +), longest: mine.max() ?? 0)
            // The longest run with a pace in the last eight weeks says the
            // most about a long race; failing that, the longest he has timed.
            let timed = runs.compactMap { date, run -> (Date, Double, Double)? in
                guard let km = run["km"] as? Double, km >= 5, let sp = run["sp"] as? Double, sp > 0
                else { return nil }
                return (date, km, sp)
            }
            let recent = timed.filter { $0.0 >= cal.date(byAdding: .day, value: -56, to: now)! }
            if let (date, km, sp) = (recent.isEmpty ? timed : recent).max(by: { $0.1 < $1.1 }) {
                let finish = RacePace.riegel(km: km, secPerKm: sp, to: Self.raceKm)
                pace = RacePace(finish: finish, perKm: finish / Self.raceKm,
                                from: String(format: "%g KM", km) + " · " + LainInfo.short(LainInfo.iso(date)))
            }
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
                // Two lines rather than an ellipsis: in the left column of the
                // two-column panel a todo lost the half that said what (15.0).
                Text(line).font(Skin.mono(13)).foregroundStyle(lines.isEmpty ? Skin.off : .white)
                    .lineLimit(2).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
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
            if let t = glance.training {
                // The week against the plan, in the words the plan uses (25.0).
                // No-break spaces inside each figure, so a narrow panel wraps
                // between the parts and not inside "0 OF 44 KM".
                Text("WEEK \(t.week) OF \(Glance.planTable.count) · \(t.phase.uppercased()) · "
                     + String(format: "%g\u{a0}OF\u{a0}%g\u{a0}KM", t.run, t.planned)
                     + " · LONG\u{a0}RUN\u{a0}" + String(format: "%g", t.longRun)
                     + (t.longest >= t.longRun ? "\u{a0}DONE" : "\u{a0}KM"))
                    .font(Skin.mono(11, .medium)).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .tourSpot("glanceTraining")
            }
            // Eight weeks, this one lit: whether the training is building is
            // the question, and one week alone cannot answer it. The plan's
            // kilometres stand behind each bar in magenta (25.0), so a short
            // week reads as short against what was meant, not against zero.
            Chart(glance.weeks) { w in
                if let p = w.planned {
                    BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("km", p),
                            stacking: .unstacked)
                        .foregroundStyle(Skin.mag.opacity(0.22))
                }
                BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("km", w.km),
                        stacking: .unstacked)
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
            if let p = glance.pace { pace(p) }
        }
        .overlay(lit(focus == .running))
    }

    /// The race at his current running (25.0, Backlog: "Race-day pacing
    /// plan"): a finish time, the even pace it means, and the clock at each
    /// quarter, from the run it was worked out from.
    private func pace(_ p: Glance.RacePace) -> some View {
        let km = Glance.raceKm
        let quarters = [0.25, 0.5, 0.75].map { f in
            String(format: "%g", km * f) + " " + Glance.clock(p.finish * f)
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "RACE · %g KM IN ~", km) + Glance.clock(p.finish)
                 + " · " + Glance.perKm(p.perKm) + "/KM")
                .font(Skin.mono(12, .semibold)).foregroundStyle(Skin.mag)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(quarters.joined(separator: " · ") + " · ESTIMATE FROM " + p.from)
                .font(Skin.mono(10)).foregroundStyle(Skin.ink)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .tourSpot("glancePace")
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
