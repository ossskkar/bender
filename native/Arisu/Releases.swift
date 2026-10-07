import SwiftUI

// MARK: - Releases
//
// Every major release of the iPad app, newest first (Oscar, 2026-10-02). Each
// one is also an annotated git tag `arisu-<version>`, which is what the Mac's
// time machine lists and builds; this file is what the app itself says about
// them. A new release adds one entry at the top, with its highlights and its
// tour, and bumps MARKETING_VERSION in the project to match.

struct Release: Identifiable {
    let version: String
    let name: String
    let date: String
    let highlights: [Highlight]
    /// The guided tour of this release. Empty for releases from before tours
    /// existed: their builds have no tour engine, so there is nothing to run.
    var tour: [TourStep] = []
    /// What the release looks like in action, playing by itself (Oscar,
    /// 2026-10-02). Empty for releases from before 21.0's demo engine.
    var demo: [DemoStep] = []
    var id: String { version }
}

struct Highlight: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let what: String
    var how: String = ""
}

/// One stop of a guided tour: which screen to be on, which control to light,
/// and what to say about it. `spot` names a `.tourSpot(_:)` in the view tree;
/// nil puts the card in the middle with no cut-out.
struct TourStep: Identifiable {
    let id = UUID()
    var scene: TourScene = .keep
    var spot: String? = nil
    let title: String
    let text: String
}

/// One stop of a demo: a screen, what is pretended on it, and for how long.
/// Everything a demo shows is local and undone when it ends: it never opens
/// the microphone, starts a call, sends a message, presses a deck key or
/// writes to the desk (Oscar, 2026-10-02).
struct DemoStep: Identifiable {
    let id = UUID()
    var scene: TourScene = .keep
    var act: DemoAct = .none
    var seconds: Double = 7
    let title: String
    let text: String
}

/// The simulated inputs a demo stop can play.
enum DemoAct {
    /// Nothing pretended: the screen as it is.
    case none
    /// A track playing on the Mac, a beat every half second.
    case music
    /// The wake line as it reads while the iPad listens for 醒来.
    case listen
    /// She is summoned: her arrival and her rings awake, no call.
    case summon
    /// 醒来 heard: what happens at the moment a call would start.
    case wake
    /// Night hours: not listening, and Singularity drifting slowly.
    case night
    /// A page pushed to this screen, as one would arrive (23.0). The page is
    /// written here; nothing is read from or written to the desk.
    case screen
    /// The page closed again, and the screen's chip in the title bar holding
    /// it (24.0). Nothing is read from the desk.
    case held
    /// The day panel beside her with its running part lit, as when he asks
    /// how his running is going (25.0). His own numbers; nothing is sent.
    case running
    /// Two pages pushed to this screen at once, the first in front, then the
    /// second (26.0). Written here; nothing is read from or written to the desk.
    case pages, pagesNext

    /// What `.pages` puts up: two of the demo's own pages, nothing fetched.
    static let pagesPage: ShowPage = {
        func one(_ title: String, _ lines: [String]) -> ShowPage {
            ShowPage(url: "about:arisu-pages-demo-" + title.lowercased(), host: title, mode: "reader",
                     title: title, text: nil, headlines: lines, ok: true, error: nil)
        }
        var first = one("Habits", ["A screen can be given several pages at once.",
                                   "Each one is a segment in the bar above, in the order they were pushed."])
        first.panels = [first, one("Health", ["The second page, one tap away.",
                                              "Both stay loaded, so going back does not reload the first."])]
        return first
    }()

    /// The page a demo stop puts up, if it puts one up.
    var page: ShowPage? {
        switch self {
        case .screen: return Self.screenPage
        case .pages, .pagesNext: return Self.pagesPage
        default: return nil
        }
    }
    /// Whether `page` is one a demo put up, to be taken down when it moves on.
    static func staged(_ page: ShowPage?) -> Bool { page == screenPage || page == pagesPage }

    /// What `.screen` puts up.
    static let screenPage = ShowPage(
        url: "about:arisu-screen-demo", host: "Screen ipad", mode: "reader", title: "Screen ipad",
        text: nil, headlines: [
            "A page pushed to the screen called ipad opens here by itself.",
            "From Claude or Hermes: screen_show with screen \"ipad\" and any address.",
            "From anywhere on the tailnet: POST /screens with name ipad and a url.",
            "Clearing the screen closes the page again.",
        ], ok: true, error: nil)

    /// Her presence on Singularity, as though she had been summoned.
    var present: Bool { self == .summon || self == .wake }
    /// What the line under her says instead of the real wake state.
    var line: String? {
        switch self {
        case .listen, .summon: return "say 醒来 to wake her"
        case .wake: return "heard 醒来"
        case .night: return "asleep until " + Night.until
        default: return nil
        }
    }
}

/// `glance` is voice mode with its chrome up, so the panel beside her shows;
/// `chatGlance` is the chat with the same panel held up (13.0).
enum TourScene { case keep, chat, chatGlance, voice, glance, singularity }

enum Releases {
    /// The version this build is, from the bundle -- the time machine stamps
    /// it on old builds too, so it is always where he landed.
    static var running: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    static var current: Release { all.first { $0.version == running } ?? all[0] }

    static let all: [Release] = [
        Release(version: "26.0", name: "Several pages", date: "2026-10-07", highlights: [
            Highlight(symbol: "figure.walk", name: "No race on the iPad",
                      what: "Project 100K was stopped on 1 October, but the iPad kept counting down to the race, "
                          + "measuring each week against the training plan and giving a race pace. All of that "
                          + "is gone: the day panel shows the kilometres of the last eight weeks and the last "
                          + "run, and Singularity's ring says the kilometres run this week. It follows lain, "
                          + "which stopped speaking about the race the same day; if the project comes back, one "
                          + "line brings it all back.",
                      how: "Open the day panel: tap her in voice mode, or ask about your running."),
            Highlight(symbol: "rectangle.split.2x1", name: "Several pages on the screen",
                      what: "lain can put up to six pages on a screen at once, and the Mac's big screen lays them "
                          + "out side by side. The iPad showed only the first. It now opens all of them in the "
                          + "same window, with a switch at the top naming each page in the order they were "
                          + "sent. Every page stays loaded, so switching back does not reload it or lose your "
                          + "place, and Safari opens the page in front.",
                      how: "Ask Claude or Hermes to show two pages on the screen called ipad, for example your "
                          + "habits and your health."),
            Highlight(symbol: "rectangle.on.rectangle", name: "All of them come back",
                      what: "The magenta key that puts the screen's page back up after you close it now brings "
                          + "back every page that was sent together, not only the first.",
                      how: "Close the window, then press the key left of the sparkles."),
            Highlight(symbol: "bolt.slash", name: "A quieter title",
                      what: "Each time the title flickered, every few seconds, the whole screen was worked out "
                          + "again: the chat, the deck, the day panel. Now only the title is. Measured in the "
                          + "simulator on the chat at rest: the screen's updates fell from 450 to 86 in twelve "
                          + "seconds, and the app's use of the processor from about 8 to about 3 percent."),
        ], tour: [
            TourStep(scene: .glance, title: "Arisu 26.0 — Several pages",
                     text: "The race is gone from the iPad, and a screen can hold several pages. Tap anywhere "
                         + "to go on."),
            TourStep(scene: .glance, spot: "glanceRunning", title: "Running, without the race",
                     text: "The last eight weeks and the last run. No countdown, plan week or race pace since "
                         + "Project 100K stopped."),
            TourStep(scene: .singularity, title: "The ring says the week",
                     text: "The magenta ring reads the kilometres run this week, as before the plan."),
            TourStep(scene: .chat, title: "Several pages at once",
                     text: "When several pages are put on the screen called ipad, they open together, with a "
                         + "switch at the top naming each one."),
            TourStep(scene: .chat, spot: "screenBack", title: "All of them come back",
                     text: "This key, lit while the screen holds pages, puts all of them back up."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Watch it",
                     text: "Behind the sparkles, WATCH THE DEMO plays this release by itself."),
        ], demo: [
            DemoStep(scene: .glance, act: .running, seconds: 8, title: "How is my running going?",
                     text: "The running part lights: the weeks and the last run, and no race any more."),
            DemoStep(scene: .chat, act: .pages, seconds: 8, title: "Two pages arrive",
                     text: "Two pages were put on the screen called ipad together, so both open, the first in "
                         + "front. These are written by the demo; nothing was asked of the desk."),
            DemoStep(scene: .chat, act: .pagesNext, seconds: 8, title: "The second one",
                     text: "The switch at the top brings the second page to the front. The first stays loaded "
                         + "behind it."),
            DemoStep(scene: .singularity, seconds: 7, title: "The ring says the week",
                     text: "The magenta ring reads the kilometres run this week, with no race beside them."),
        ]),
        Release(version: "25.0", name: "Race month", date: "2026-10-07", highlights: [
            Highlight(symbol: "figure.run", name: "The week against the plan",
                      what: "The running part of the day panel now knows Project 100K's 14-week plan. A line "
                          + "says which week of the plan this is, what kind of week, how many kilometres are "
                          + "run of how many planned, and the long run it asks for. In the chart each week's "
                          + "planned kilometres stand behind its bar in magenta, so a short week shows as "
                          + "short against the plan rather than against nothing. The plan moves with the race "
                          + "date, as the running system's own does.",
                      how: "Open the panel: tap her in voice mode, or ask about your running."),
            Highlight(symbol: "stopwatch", name: "A race pace",
                      what: "Under the last run, the panel gives a finish time for the 100 km, the even pace "
                          + "per kilometre it means, and the clock at 25, 50 and 75 km. It is worked out from "
                          + "your longest timed run of the last eight weeks with a common race-time formula, "
                          + "and says which run it used. It is an estimate; past a marathon the formula tends "
                          + "to promise too much, so treat it as the fastest sensible plan.",
                      how: "Look under LAST RUN in the panel."),
            Highlight(symbol: "circle.dashed", name: "The rings say the week",
                      what: "Singularity's magenta ring said only how many kilometres were run this week. It "
                          + "now says the plan's week, its kind and the kilometres run of those planned, and "
                          + "the race pace, beside the days to the race."),
        ], tour: [
            TourStep(scene: .glance, title: "Arisu 25.0 — Race month",
                     text: "A month to the 100 km: the panel beside her now measures the running against "
                         + "the plan. Tap anywhere to go on."),
            TourStep(scene: .glance, spot: "glanceTraining", title: "This week of the plan",
                     text: "Which week of fourteen, what kind, the kilometres run of those planned and the "
                         + "long run it asks for."),
            TourStep(scene: .glance, spot: "glanceRunning", title: "Planned behind run",
                     text: "Each week's planned kilometres stand in magenta behind what was run."),
            TourStep(scene: .glance, spot: "glancePace", title: "A race pace",
                     text: "A finish time and even pace for 100 km, from your longest recent timed run. "
                         + "An estimate, and it says which run it used."),
            TourStep(scene: .singularity, title: "The rings say the week",
                     text: "The magenta ring reads the plan's week and the race pace too."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Watch it",
                     text: "Behind the sparkles, WATCH THE DEMO plays this release by itself."),
        ], demo: [
            DemoStep(scene: .glance, act: .running, seconds: 8, title: "How is my running going?",
                     text: "Asked about his running, the panel lights its running part: this week of the "
                         + "plan, and the plan behind each week's bar. His own numbers, read from lain."),
            DemoStep(scene: .glance, act: .running, seconds: 8, title: "The race at this running",
                     text: "Under the last run: a finish time for 100 km, the pace it means and the clock "
                         + "at each quarter, and the run it came from."),
            DemoStep(scene: .singularity, seconds: 8, title: "The rings say the week",
                     text: "The magenta ring reads the week of the plan, the kilometres run of those planned and the race pace."),
        ]),
        Release(version: "24.0", name: "Way back", date: "2026-10-07", highlights: [
            Highlight(symbol: "rectangle.on.rectangle", name: "Back to the screen",
                      what: "While lain's screen called ipad holds a page, a magenta key sits in the title bar. "
                          + "Closing the page no longer loses it: one press puts it back up. A long press lists "
                          + "the pages the screen showed before, newest first, and opens any of them. Only "
                          + "this iPad's view changes; what the screen holds stays as the desk has it.",
                      how: "Close a page that was put on the ipad screen, then press the key left of the "
                          + "sparkles; hold it for the earlier pages."),
            Highlight(symbol: "lightbulb", name: "The Light key tells the truth",
                      what: "The Light key read God's Eye once, when the deck opened. When lain was busy with "
                          + "the strip it answered with no lights, and the key stayed unsure for good, so a "
                          + "press guessed. It now asks again a few seconds later, again each time the iPad "
                          + "comes back to the app, and once more just before a press if it still does not "
                          + "know. When lain says the strip refused, the key turns red instead of green.",
                      how: "Press Light in the Deck's top row."),
            Highlight(symbol: "circle.dashed", name: "Her eye without blurs",
                      what: "Singularity's eye was drawn with ten blurred passes a picture, each one a copy "
                          + "of the whole screen: its rings, its photon ring, its smoke and the glow of the "
                          + "mesh behind it. They are now soft gradients and a wide faint line, which look "
                          + "the same and need no copy. The simulator draws this screen at about 20 a second "
                          + "with or without any blur, so the saving shows on the iPad, not here."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 24.0 — Way back",
                     text: "A page put on this iPad can be found again after you close it. Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "screenBack", title: "Back to the screen",
                     text: "This key is lit while the ipad screen holds a page. Press it to put the page back up."),
            TourStep(scene: .chat, spot: "screenBack", title: "What it showed before",
                     text: "Hold the same key for the pages the screen showed earlier, newest first."),
            TourStep(scene: .chat, spot: "deck", title: "An honest Light key",
                     text: "Light asks lain again when it was not sure, and turns red when the strip refused."),
            TourStep(scene: .singularity, title: "Her eye, lighter",
                     text: "The eye and the mesh behind it are drawn without blurs now: the same picture, "
                         + "ten fewer copies of the screen each time."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Watch it",
                     text: "Behind the sparkles, WATCH THE DEMO plays this release by itself."),
        ], demo: [
            DemoStep(scene: .chat, act: .screen, seconds: 8, title: "A page arrives",
                     text: "Something was put on the screen called ipad, so it opens. This one is written "
                         + "by the demo; nothing was asked of the desk."),
            DemoStep(scene: .chat, act: .held, seconds: 8, title: "Closed, not gone",
                     text: "The page is closed, and the key left of the sparkles is lit: the screen still "
                         + "holds it, and one press brings it back."),
            DemoStep(scene: .singularity, seconds: 7, title: "Her eye, lighter",
                     text: "The eye, its smoke and the mesh, drawn with gradients instead of blurs."),
        ]),
        Release(version: "23.0", name: "On screen", date: "2026-10-07", highlights: [
            Highlight(symbol: "rectangle.on.rectangle", name: "The iPad is a screen",
                      what: "lain keeps a list of named screens and what each one shows; the Mac's desk "
                          + "canvas already read it. The iPad now reads it too, as the screen called ipad: a "
                          + "page put there opens on the iPad by itself within a few seconds, over whatever "
                          + "is on screen. lain's own pages open as they are; other sites go through the "
                          + "desk's reader as her pages always have. Clearing the screen closes the page. "
                          + "Each page opens once, not again at every launch.",
                      how: "Ask Claude or Hermes to show a page on the screen called ipad (screen_show, "
                          + "screen \"ipad\"), or POST /screens with name ipad and a url."),
            Highlight(symbol: "moon.zzz", name: "Her sleeping face",
                      what: "At night, with no call, she is drawn the way she sleeps: half as bright, a third "
                          + "as fast, a quarter of the pictures a second, and no longer moving with the Mac's "
                          + "music, which the iPad stops asking about until morning. A call wakes her face "
                          + "with her.",
                      how: "Look at her in Classic after the hour set in Settings, Night."),
            Highlight(symbol: "circle.dashed", name: "Singularity's apps cost less",
                      what: "The app icons, their names, the spiral arms and the chosen app's actions round the "
                          + "outside each had their own glow, every picture. They are now gathered and drawn "
                          + "together, one glow for each kind, the way 22.0 drew the falling words. Measured "
                          + "in the simulator on the same screen: 57 percent of a core instead of 73, at the "
                          + "same rate of pictures."),
        ], tour: [
            TourStep(scene: .voice, title: "Arisu 23.0 — On screen",
                     text: "The iPad is now a screen lain can put a page on, by the name ipad. Tap anywhere "
                         + "to go on."),
            TourStep(scene: .chat, title: "A page arrives by itself",
                     text: "Ask Claude or Hermes to show something on the screen called ipad. It opens here "
                         + "within a few seconds; clearing the screen closes it."),
            TourStep(scene: .voice, title: "Her sleeping face",
                     text: "At night, with no call, she is drawn dim and slow and stops moving with the "
                         + "Mac's music. A call wakes her."),
            TourStep(scene: .singularity, title: "Lighter apps",
                     text: "The icons, names, arms and actions are drawn together now: about a fifth less "
                         + "work, the same picture."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Watch it",
                     text: "Behind the sparkles, WATCH THE DEMO plays this release by itself."),
        ], demo: [
            DemoStep(scene: .chat, act: .screen, seconds: 9, title: "A page arrives",
                     text: "Something was put on the screen called ipad, so it opens by itself. This one is "
                         + "written by the demo; nothing was asked of the desk."),
            DemoStep(scene: .voice, act: .night, seconds: 8, title: "Her sleeping face",
                     text: "At night she is drawn dim and slow, and the line under her says until when."),
            DemoStep(scene: .voice, seconds: 6, title: "Awake",
                     text: "The same face by day, for comparison: full light, full speed."),
            DemoStep(scene: .singularity, seconds: 7, title: "Lighter apps",
                     text: "The icons, names, arms and actions round her, drawn together: the same picture "
                         + "for about a fifth less work."),
        ]),
        Release(version: "22.0", name: "Night", date: "2026-10-07", highlights: [
            Highlight(symbol: "moon.zzz", name: "She sleeps at night",
                      what: "From 23:00 until 07:00 she no longer listens for 醒来: the iPad's microphone stays "
                          + "off all night and cannot be woken by the room, a film or the baby. The line under "
                          + "her and Singularity's rim say ASLEEP UNTIL 07:00, and Singularity draws half as "
                          + "often to spare the battery. A touch still brings her: hold Singularity, tap twice "
                          + "or tap the microphone. In the morning she listens again by herself.",
                      how: "Settings, Night: choose when she goes to sleep and when she wakes. The same hour "
                          + "twice switches night off."),
            Highlight(symbol: "circle.dashed", name: "Singularity's falling words cost half",
                      what: "The words falling down the spiral arms were each laid out and blurred on their own, "
                          + "every picture: more than half of Singularity's work. They are now made once as "
                          + "shapes and drawn together. Measured in the simulator: 17 pictures a second instead "
                          + "of 11, with less of the processor, so about 45 percent less work per picture. At "
                          + "night it uses 55 percent of a core where it used 87."),
            Highlight(symbol: "arrow.triangle.2.circlepath", name: "One reader of your day",
                      what: "Singularity read lain's data for its rings separately from the rest of the app, "
                          + "so the same file was fetched twice. Both now share one reader."),
        ], tour: [
            TourStep(scene: .singularity, title: "Arisu 22.0 — Night",
                     text: "From 23:00 to 07:00 she does not listen for 醒来. The rim says ASLEEP UNTIL 07:00 "
                         + "and Singularity draws half as often. Tap anywhere to go on."),
            TourStep(scene: .voice, title: "The same in Classic",
                     text: "The line under her says it too. A touch still brings her: tap twice, or tap the "
                         + "microphone."),
            TourStep(scene: .chat, spot: "settings", title: "Your hours",
                     text: "Settings, Night: when she goes to sleep and when she wakes. The same hour twice "
                         + "switches night off."),
            TourStep(scene: .singularity, title: "Lighter arms",
                     text: "The words falling down the arms are drawn together now, as shapes made once: "
                         + "about half the work per picture."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Watch it",
                     text: "Behind the sparkles, WATCH THE DEMO plays this release by itself."),
        ], demo: [
            DemoStep(scene: .singularity, act: .night, seconds: 8, title: "Night on Singularity",
                     text: "From bedtime until morning she is not listening. The rim says ASLEEP UNTIL 07:00 "
                         + "and Singularity draws half as often."),
            DemoStep(scene: .glance, act: .night, seconds: 7, title: "Night in Classic",
                     text: "The line under her says the same. The microphone stays off all night."),
            DemoStep(scene: .singularity, act: .summon, seconds: 9, title: "A touch still brings her",
                     text: "Held at night, Singularity brings her as it does by day. Only the listening for "
                         + "醒来 sleeps."),
            DemoStep(scene: .singularity, seconds: 7, title: "Lighter arms",
                     text: "The words falling down the spiral arms, drawn together as shapes: about half the "
                         + "work per picture, so more pictures a second for less battery."),
        ]),
        Release(version: "21.0", name: "Summoned", date: "2026-10-07", highlights: [
            Highlight(symbol: "play.rectangle", name: "Watch the demo",
                      what: "Next to TAKE THE TOUR there is now WATCH THE DEMO: the release plays by itself. "
                          + "The screens change, music plays on Singularity, she arrives, and a caption at "
                          + "the bottom says what you are looking at. Nothing in a demo is real: no "
                          + "microphone, no call, no message, no key pressed on the Mac, and everything is "
                          + "put back when it ends. 20.0's music and wake line have a demo too, under RELEASES.",
                      how: "Tap the sparkles, then WATCH THE DEMO. Tap anywhere to stop it."),
            Highlight(symbol: "eye", name: "Summon her without a call",
                      what: "On Singularity, holding a finger anywhere brings her: the dark, the flash, her "
                          + "name and the rings awake, as in a conversation, but no call opens and nothing is "
                          + "paid for. The rim says SAY 醒来 TO WAKE HER; saying it starts the call and she "
                          + "speaks her line. Hold again and she goes. After ten minutes without 醒来 she goes "
                          + "by herself, to spare the battery. Two taps still start a call straight away.",
                      how: "On Singularity, hold a finger anywhere for half a second, then say 醒来."),
            Highlight(symbol: "ear", name: "The wake line on Singularity",
                      what: "20.0 said Singularity would show whether she can hear 醒来; only Classic did. "
                          + "Singularity's outer rim now says it after HOLD TO SUMMON: SAY 醒来 TO WAKE HER, "
                          + "or why she cannot hear it.",
                      how: "Read the outer rim on Singularity, after the time."),
            Highlight(symbol: "tray", name: "Test builds leave your brief alone",
                      what: "The app in the Mac's simulator, which the builder agents start to check their "
                          + "work, used to collect what Hermes had queued for you, such as a morning brief, "
                          + "and say it in a call nobody heard. The simulator no longer collects anything, so "
                          + "it waits for your iPad."),
            Highlight(symbol: "rectangle.portrait", name: "Brain dumps read upright",
                      what: "With the iPad held upright, the REC//BRAIN_DUMP panel had room for one letter per "
                          + "line. When it is narrow it now puts the log under the button and the tabs under "
                          + "the title. In landscape nothing changes.",
                      how: "Turn the iPad upright and look at the panel above the deck."),
        ], tour: [
            TourStep(scene: .singularity, title: "Arisu 21.0 — Summoned",
                     text: "Hold a finger anywhere on Singularity and she arrives, with no call behind her. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .singularity, title: "醒来 starts the call",
                     text: "While she is here the rim says SAY 醒来 TO WAKE HER. Saying it opens the call and "
                         + "she speaks; holding again sends her away."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Watch the demo",
                     text: "Behind the sparkles, WATCH THE DEMO plays a release by itself. Nothing in it is "
                         + "real: no microphone, no call, no key pressed on the Mac."),
            TourStep(scene: .chat, spot: "record", title: "Brain dumps, upright",
                     text: "Held upright, this panel puts the log under the button instead of one letter "
                         + "per line."),
            TourStep(scene: .chat, title: "Your brief stays yours",
                     text: "Test builds on the Mac no longer collect what Hermes queues for you; your iPad "
                         + "does."),
        ], demo: [
            DemoStep(scene: .singularity, seconds: 7, title: "Singularity, at rest",
                     text: "Her eye is a black hole and the apps of the deck fall into it. The rim says "
                         + "HOLD TO SUMMON."),
            DemoStep(scene: .singularity, act: .summon, seconds: 9, title: "Held: she arrives",
                     text: "A long press brings her: the dark, the flash, her name, the rings awake. No call "
                         + "is open. The rim says SAY 醒来 TO WAKE HER."),
            DemoStep(scene: .singularity, act: .wake, seconds: 10, title: "醒来",
                     text: "When she hears it, the call opens and she speaks her line, carved in runes. In "
                         + "the demo the line burns and nobody speaks."),
            DemoStep(scene: .singularity, seconds: 5, title: "Held again: she goes",
                     text: "Another long press sends her away, and ends the call if one is on."),
        ]),
        Release(version: "20.0", name: "Loud", date: "2026-10-02", highlights: [
            Highlight(symbol: "waveform.path.ecg", name: "Music explodes on Singularity",
                      what: "While she is away and Spotify plays on the Mac, every beat throws a ring of light "
                          + "to the edge of the screen and sends a shockwave through space. The louder the "
                          + "music, the more space bends and twists, and the colours turn through cyan, "
                          + "magenta and violet. When the music stops, she goes back to her own cyan.",
                      how: "Pick SINGULARITY and play something in Spotify on the Mac."),
            Highlight(symbol: "ear", name: "Wake her with 醒来, and see whether she can hear it",
                      what: "Whenever no call is on, in Classic and Singularity alike, she listens for 醒来. "
                          + "She now also accepts how the iPad often writes that word (星来, 兴来, 行来). "
                          + "The line under her says SAY 醒来 TO WAKE HER while she is listening, or why "
                          + "she cannot, for example when Chinese is missing as a dictation language.",
                      how: "Say 醒来 with the app open and no call on. If the line says WAKE WORD OFF, do "
                          + "what it says."),
        ], tour: [
            TourStep(scene: .singularity, title: "Arisu 20.0 — Loud",
                     text: "Play music on the Mac: every beat is a shockwave of light, space bends with the "
                         + "music and the colours turn with it."),
            TourStep(scene: .singularity, title: "Wake her by voice",
                     text: "With no call on, say 醒来. The line at the bottom says whether she is listening "
                         + "for it, or why she cannot."),
        ], demo: [
            // Added in 21.0, when demos began; the highlights above are 20.0's own.
            DemoStep(scene: .singularity, act: .music, seconds: 12, title: "Music explodes on Singularity",
                     text: "A track playing on the Mac, pretended here: every beat throws a ring of light to "
                         + "the edge, space bends with it and the colours turn."),
            DemoStep(scene: .singularity, act: .listen, seconds: 7, title: "The music stops",
                     text: "She goes back to her own cyan. With no call on, the rim says SAY 醒来 TO WAKE HER, "
                         + "or why she cannot hear it."),
            DemoStep(scene: .glance, act: .listen, seconds: 7, title: "The same line in Classic",
                     text: "In voice mode the bar under her says it too."),
            DemoStep(scene: .singularity, act: .wake, seconds: 10, title: "醒来 heard",
                     text: "She arrives and the call starts with her line. In the demo, no call does."),
        ]),
        Release(version: "19.0", name: "Light rings", date: "2026-10-02", highlights: [
            Highlight(symbol: "circle.dashed", name: "Singularity costs a quarter of what it did",
                      what: "The words turning on Singularity's rings were laid out letter by letter, sixty "
                          + "times a second, which kept a whole processor core busy with nothing happening. "
                          + "Each ring is now one shape, its letters made once and reused. Measured in the "
                          + "simulator: four times less work per picture, so it moves more smoothly and the "
                          + "battery lasts longer."),
            Highlight(symbol: "tortoise", name: "Slower when she is away",
                      what: "While she is not in a call, Singularity draws thirty pictures a second instead "
                          + "of sixty. Space only drifts then; the difference cannot be seen, the battery "
                          + "can. When she arrives it goes back to sixty."),
            Highlight(symbol: "person.2.wave.2", name: "Your agents on the rim",
                      what: "The builder agents that are working now ride Singularity's outer rim, after "
                          + "the clock: the agent's name, AT WORK, and what it last said. The same news the "
                          + "deck shows above its buttons in Classic, refreshed every half minute. When no "
                          + "agent is working, the rim is as before.",
                      how: "Switch to Singularity and read the outer rim, after the time."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 19.0 — Light rings",
                     text: "Singularity does a quarter of the work it did, and shows your agents. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .singularity, title: "Lighter rings",
                     text: "Each ring of words is now one shape, made once, so Singularity moves more "
                         + "smoothly and keeps the iPad cooler. With her away it draws half as often."),
            TourStep(scene: .singularity, title: "Your agents on the rim",
                     text: "Read the outer rim after the time: every builder agent at work, with what it "
                         + "last said. Nothing extra shows when none is working."),
            TourStep(scene: .chat, spot: "agents", title: "The same news in Classic",
                     text: "Above the deck's buttons, as in 18.0. Tap AGENTS to open lain's Agents page."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "18.0", name: "At work", date: "2026-10-02", highlights: [
            Highlight(symbol: "person.2.wave.2", name: "Your agents, above the deck",
                      what: "The empty space above the deck's buttons now shows what each builder agent is "
                          + "doing: its name, working, done or failed, its last message in its own words, "
                          + "and how long ago. The same news as lain's Agents page, refreshed every half "
                          + "minute. When space is short it shows less, and the buttons never move.",
                      how: "Look above the deck's buttons. Tap AGENTS to open lain's Agents page."),
            Highlight(symbol: "waveform", name: "Only her face moves during a call",
                      what: "Every change in her voice's loudness, twenty a second, used to rebuild the whole "
                          + "screen: chat, deck and brain dumps included. Now only her face redraws. Measured "
                          + "in the simulator with her level moving as in a call: from 94 percent of a "
                          + "processor core to under 1 percent."),
            Highlight(symbol: "music.note", name: "A quieter line from the Mac",
                      what: "The Mac sent the music level thirty times a second even with nothing playing, "
                          + "and each one redrew her face. It now sends a change, or one line a second, and "
                          + "the deck no longer redraws every two seconds to say the same app is in front."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 18.0 — At work",
                     text: "Your builder agents are on the iPad now, and a call costs the iPad far less. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "agents", title: "Your agents",
                     text: "Each agent on one line: working, done or failed, what it last said, and how long "
                         + "ago. Working ones come first. Tap AGENTS to open lain's Agents page."),
            TourStep(scene: .voice, spot: "her", title: "Only her face moves",
                     text: "During a call, her face follows her voice and nothing else on screen is rebuilt, "
                         + "so the deck and the chat stay still and the battery lasts longer."),
            TourStep(scene: .chat, spot: "deck", title: "A quieter Mac",
                     text: "The deck and her face are redrawn only when the Mac has something new to say, "
                         + "not several times a second with the same news."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "17.0", name: "Steady", date: "2026-10-02", highlights: [
            Highlight(symbol: "battery.100", name: "The screen rests when nothing changes",
                      what: "With nobody talking, the app was redrawing the whole screen, chat, deck and "
                          + "brain dumps, twenty times a second, which kept about one processor core busy all "
                          + "day. It now redraws only what changed. Measured in the simulator: from 96 percent "
                          + "of a core to under 1 percent with the chat open."),
            Highlight(symbol: "text.bubble", name: "A calmer chat during a call",
                      what: "When you type while she is listening, the chat no longer redraws with every "
                          + "movement of her voice, and each message is formatted once instead of on every "
                          + "redraw. Long conversations scroll more smoothly."),
            Highlight(symbol: "rectangle.portrait.on.rectangle.portrait", name: "Pages she puts up open in the chat",
                      what: "When she puts a page on your screen while you are reading the chat, it now opens "
                          + "in the app's page window straight away, with her line about it in the chat. It "
                          + "used to wait until your next call, or up to an hour.",
                      how: "Ask her in a call to show you a page, then go back to the chat; or wait for one "
                          + "she sends on her own."),
            Highlight(symbol: "checkmark.seal", name: "A clean build",
                      what: "Seven small faults the build tools pointed out are fixed, so a new warning "
                          + "stands out the day it appears."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 17.0 — Steady",
                     text: "Nothing new to learn in this one: the app does less work and keeps up with her. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "thread", title: "Pages she puts up open here",
                     text: "When she puts a page on your screen while you read, her line lands here and the "
                         + "page opens in the app's page window at once."),
            TourStep(scene: .chat, spot: "thread", title: "A calmer chat",
                     text: "Each message is formatted once, and the chat no longer redraws with every "
                         + "movement of her voice."),
            TourStep(scene: .chat, spot: "deck", title: "The screen rests",
                     text: "The deck, the brain dumps and the chat used to be redrawn twenty times a second "
                         + "with nobody talking. Now they are redrawn only when something on them changes."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "16.0", name: "On the page", date: "2026-10-02", highlights: [
            Highlight(symbol: "bold", name: "Bold reads as bold",
                      what: "When she marks words in bold, they are now shown in bold, and a line she starts "
                          + "with an asterisk is a bullet. Her lists, such as the emails waiting for you, "
                          + "used to show the raw asterisks around every name.",
                      how: "Ask her in the chat what is in your inbox."),
            Highlight(symbol: "rectangle.portrait.on.rectangle.portrait", name: "Pages from the chat",
                      what: "When her answer contains a web address, a small button with the site's name "
                          + "appears under it. It opens the page inside the app, in the same window a call "
                          + "uses: the site itself, or its headlines or text when that reads better. No call "
                          + "is started. Tapping the address itself still opens your browser.",
                      how: "Tap the button with the site's name under her answer."),
            Highlight(symbol: "ellipsis.bubble", name: "Suggestions wait while she thinks",
                      what: "The suggested answers and commands above the typing field step aside while she "
                          + "is working on an answer, and come back fresh when she has replied. They were "
                          + "made for her previous line, and a command tapped then did nothing.",
                      how: "Send her a message and watch the rows above the field."),
            Highlight(symbol: "rectangle.portrait.rotate", name: "Brain dumps keep your place",
                      what: "When you turn the iPad or move the divider, the Record panel's log stays on your "
                          + "newest dump, as the chat already did."),
            Highlight(symbol: "battery.100", name: "Less work in the background",
                      what: "The app no longer sets up and throws away a microphone engine several times a "
                          + "second while she is on screen. It was invisible, but it cost battery all day."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 16.0 — On the page",
                     text: "Her answers read better, and the pages she mentions open inside the app. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "thread", title: "Bold reads as bold",
                     text: "Words she marks in bold are bold now, and her lists have bullets instead of "
                         + "asterisks around every name."),
            TourStep(scene: .chat, spot: "pageChip", title: "Pages from the chat",
                     text: "When she gives you a web address, a button with the site's name sits under her "
                         + "answer. It opens the page inside the app without starting a call."),
            TourStep(scene: .chat, spot: "composer", title: "Suggestions wait while she thinks",
                     text: "The suggested answers and commands step aside while she works on an answer and "
                         + "come back fresh after it."),
            TourStep(scene: .chat, spot: "record", title: "Brain dumps keep your place",
                     text: "Turn the iPad or move the divider: the log stays on your newest dump."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "15.0", name: "Next line", date: "2026-10-02", highlights: [
            Highlight(symbol: "text.bubble", name: "Your likely answers",
                      what: "Above the typing field, four answers to what she just said, the most likely one "
                          + "lit in magenta. Tapping one puts it in the field, where you can change it or "
                          + "send it as it is. Nothing is sent until you press Send.",
                      how: "Open the chat and tap one of the answers above the field."),
            Highlight(symbol: "chevron.right.2", name: "Commands for the moment",
                      what: "A row of commands made for right now, from the time of day, today's plan and "
                          + "what you were just talking about. Tapping one sends it as your message, the "
                          + "same as typing it. They change after every answer and every few minutes.",
                      how: "Tap a command that starts with >. Swipe a row sideways to see the rest."),
            Highlight(symbol: "text.alignleft", name: "Full lines in the day panel",
                      what: "In the day panel, plan blocks and things that are due wrap onto a second line "
                          + "instead of being cut short in the narrow column."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 15.0 — Next line",
                     text: "The chat now suggests what to say next, the same as the chat in the browser. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "suggestReplies", title: "Your likely answers",
                     text: "Four answers to her last line, the most likely one lit. Tap one and it goes into "
                         + "the field for you to change or send. It is not sent for you."),
            TourStep(scene: .chat, spot: "suggestCommands", title: "Commands for the moment",
                     text: "Made from the time, your plan and the conversation. Tap one and it is sent as your "
                         + "message. Swipe the row sideways for more."),
            TourStep(scene: .chat, spot: "composer", title: "Always fresh",
                     text: "Both rows change after every answer she gives and every minute while the chat is "
                         + "open. If the desk is slow, the last ones stay."),
            TourStep(scene: .chatGlance, spot: "chatGlance", title: "Full lines in the day panel",
                     text: "Plan blocks and things that are due wrap onto a second line instead of being cut short."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "14.0", name: "Landscape", date: "2026-10-02", highlights: [
            Highlight(symbol: "rectangle.portrait.rotate", name: "Turning the iPad keeps your place",
                      what: "When you turn the iPad, open or close the day panel, or move the divider, the "
                          + "chat stays on the newest message. Turning it used to leave the chat in the "
                          + "middle of an old answer, or blank until you scrolled.",
                      how: "Turn the iPad while a long conversation is open."),
            Highlight(symbol: "rectangle.split.2x1", name: "Your day in two columns",
                      what: "With the iPad on its side, the day panel above the chat is laid out in two "
                          + "columns: the plan and what is due on the left, running and habits on the right. "
                          + "It takes about a third of the chat's height instead of two thirds.",
                      how: "In landscape, press the panel button next to Send."),
            Highlight(symbol: "text.below.photo", name: "Tour cards beside what they explain",
                      what: "In a guided tour, when a lit control is too tall for the card to fit above or "
                          + "below it, as voice mode is in landscape, the card now sits beside it "
                          + "instead of covering it.",
                      how: "Sparkles, then TAKE THE TOUR, with the iPad on its side."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 14.0 — Landscape",
                     text: "This release is about the iPad on its side, the way it stands on the desk. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "thread", title: "Your place is kept",
                     text: "Turn the iPad, open the day panel or drag the divider: the chat stays on the "
                         + "newest message instead of jumping into an old answer or going blank."),
            TourStep(scene: .chatGlance, spot: "chatGlance", title: "Your day in two columns",
                     text: "In landscape the panel above the chat has two columns: the plan and what is due "
                         + "on the left, running and habits on the right. More of the chat stays visible."),
            TourStep(scene: .chat, spot: "chatGlanceButton", title: "The panel button",
                     text: "Opens and closes the panel, as before. Upright, the panel keeps one column, "
                         + "because two would be too narrow to read."),
            TourStep(scene: .voice, spot: "her", title: "Cards beside what they explain",
                     text: "When the lit part is too tall for this card to fit above or below it, as voice "
                         + "mode is with the iPad on its side, the card sits beside it instead of covering it."),
            TourStep(scene: .glance, spot: "glance", title: "Beside her, sideways",
                     text: "Voice mode with the iPad on its side: the panel at her top left, the bubbles on "
                         + "the right, and her in the middle."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "13.0", name: "Chat at a glance", date: "2026-10-02", highlights: [
            Highlight(symbol: "rectangle.leadinghalf.inset.filled", name: "Your day in the chat",
                      what: "The panel from voice mode, with the plan, what is due, the running chart and the "
                          + "habits week, now opens in the typed chat too. It sits beside the conversation "
                          + "when the screen is wide and above it when it is narrow.",
                      how: "Press the panel button next to Send. Press it again to close it. It stays the "
                          + "way you left it."),
            Highlight(symbol: "text.bubble", name: "Typed questions bring the chart",
                      what: "When you type about your running or habits, or she answers about them, the panel "
                          + "comes up by itself with that chart lit, as it does when you talk to her.",
                      how: "Type \"How is my running going?\" in the chat."),
            Highlight(symbol: "sun.max", name: "One greeting",
                      what: "A new conversation opens with her greeting once. Starting new conversations "
                          + "quickly one after another could show \"Good morning\" two or three times."),
            Highlight(symbol: "keyboard", name: "Newest messages stay in view",
                      what: "When the keyboard comes up, the chat moves to the latest messages instead of "
                          + "leaving them hidden behind it."),
            Highlight(symbol: "checkmark.square", name: "Full habit names",
                      what: "Habit names in the panel wrap onto a second line instead of being cut short "
                          + "when the iPad is upright."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 13.0 — Chat at a glance",
                     text: "Your day, which 12.0 put next to her in voice mode, now comes to the typed chat. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "chatGlanceButton", title: "The panel button",
                     text: "Next to Send. Press it to open your day beside the conversation; press it again "
                         + "to close it. It stays open or closed until you change it."),
            TourStep(scene: .chatGlance, spot: "chatGlance", title: "Your day in the chat",
                     text: "The plan, the running chart, the habits week and what is due, read from lain "
                         + "every five minutes. Beside the chat when the screen is wide, above it when narrow."),
            TourStep(scene: .glance, spot: "glanceHabits", title: "Full habit names",
                     text: "Beside her in voice mode the panel is narrower. Names that do not fit now wrap "
                         + "onto a second line instead of being cut short."),
            TourStep(scene: .chat, spot: "composer", title: "Typed questions bring the chart",
                     text: "Type about your running or habits and the panel comes up by itself with that "
                         + "chart lit. When the keyboard comes up, the newest messages stay in view."),
            TourStep(scene: .chat, title: "One greeting",
                     text: "+ or a two-finger double tap starts a new conversation, and her greeting now "
                         + "appears once however quickly you press."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "12.0", name: "At a glance", date: "2026-10-02", highlights: [
            Highlight(symbol: "rectangle.leadinghalf.inset.filled", name: "Today beside her",
                      what: "In voice mode a panel shows your day next to her: what is next on the plan, "
                          + "what is due, your running and your habits. She moves aside to make room.",
                      how: "Go to voice mode and tap the screen once. Tap again to hide it."),
            Highlight(symbol: "chart.bar", name: "Running chart",
                      what: "Kilometres per week for the last eight weeks, this week lit, the days left to "
                          + "the race and your last run with its pace."),
            Highlight(symbol: "checkmark.square", name: "Habits week",
                      what: "Each habit with the last seven days as squares, green where it was done, and "
                          + "today's count for habits with a target, such as water."),
            Highlight(symbol: "text.bubble", name: "Charts come with the answer",
                      what: "When you or she talk about running or habits, the panel comes up by itself with "
                          + "that chart lit, and goes again a minute and a half later.",
                      how: "Ask \"How is my running going?\" or press the HOW'S MY RUNNING? bubble."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 12.0 — At a glance",
                     text: "Your day now sits next to her in voice mode, with charts for running and habits. "
                         + "Tap anywhere to go on."),
            TourStep(scene: .glance, spot: "glance", title: "Today beside her",
                     text: "In voice mode, one tap on the screen brings this panel up with the transcript and "
                         + "the bubbles. It reads lain, the same data as the dashboard, every five minutes."),
            TourStep(scene: .glance, spot: "glanceToday", title: "Next",
                     text: "The next three blocks still to come on today's plan."),
            TourStep(scene: .glance, spot: "glanceRunning", title: "Running",
                     text: "Kilometres per week for eight weeks, this week brightest. On top, the days left "
                         + "to the race; below, your last run and its pace."),
            TourStep(scene: .glance, spot: "glanceHabits", title: "Habits",
                     text: "Seven squares per habit, today on the right: green is done, an empty square is "
                         + "missed, and no square means it was not due. Water shows today's glasses."),
            TourStep(scene: .glance, spot: "commands", title: "Charts come with the answer",
                     text: "Ask about your running or habits, by voice or with these bubbles, and the panel "
                         + "comes up by itself with that chart lit."),
            TourStep(scene: .chat, spot: "whatsNew", title: "Earlier releases",
                     text: "Behind the sparkles: every release, this tour again, and the time machine."),
        ]),
        Release(version: "11.0", name: "Time machine", date: "2026-10-02", highlights: [
            Highlight(symbol: "clock.arrow.circlepath", name: "Time machine",
                      what: "Every version of this app, back to the very first one from 9 September, can be "
                          + "put on the iPad again. The Mac builds it and installs it, and the app reopens "
                          + "as that version. Your settings stay.",
                      how: "Sparkles in the title bar, then TIME MACHINE. Pick a release and press TRAVEL. "
                          + "The first trip to a version takes two to four minutes; after that it is quick."),
            Highlight(symbol: "arrow.uturn.backward", name: "Coming back",
                      what: "Versions before 11.0 have no time machine of their own.",
                      how: "Open the time machine page in Safari on the iPad and press TRAVEL on the newest "
                          + "release. The link is at the bottom of the TIME MACHINE tab."),
            Highlight(symbol: "map", name: "Guided tours",
                      what: "Each release from now on comes with a tour. It lights up each control on the real "
                          + "screen and explains it. The tour starts by itself the first time a new version "
                          + "opens.",
                      how: "Tap anywhere to go on. SKIP ends it. To see it again: sparkles, then TAKE THE TOUR."),
            Highlight(symbol: "number", name: "Release labels",
                      what: "The app's history is labelled as releases 0.1 to 11.0, each with a name and its "
                          + "highlights. The version you are on is marked YOU ARE HERE."),
        ], tour: [
            TourStep(scene: .chat, title: "Arisu 11.0 — Time machine",
                     text: "A short tour of the app as it is today, and of what is new. Tap anywhere to go on."),
            TourStep(scene: .chat, spot: "title", title: "Versions",
                     text: "The title is a menu: CLASSIC is this screen, SINGULARITY is the full-screen "
                         + "black hole. A three-finger swipe left or right switches between them too."),
            TourStep(scene: .chat, spot: "record", title: "Brain dump",
                     text: "Press REC and speak. The Mac goes quiet while you record. Your logs are listed "
                         + "next to the button."),
            TourStep(scene: .chat, spot: "deck", title: "The deck",
                     text: "Your Mac's apps, each with its own keys. Turn the wheel to an app and tap its name "
                         + "to open it on the Mac. The keys you use most move to the front."),
            TourStep(scene: .chat, spot: "composer", title: "Chat",
                     text: "Type to her here. The clock is the history and + starts a new conversation, which "
                         + "opens with her greeting and the three things that matter today."),
            TourStep(scene: .chat, spot: "voiceButton", title: "Voice",
                     text: "This puts you in voice mode. The microphone starts muted, so it only listens once "
                         + "you unmute. In the chat, a double tap does the same."),
            TourStep(scene: .voice, spot: "her", title: "Voice mode",
                     text: "Only her animation is shown. Tap once to see what was said and the command bubbles "
                         + "(brief, week, AI signals); tap again to hide them."),
            TourStep(scene: .singularity, title: "Singularity",
                     text: "Hold anywhere and she arrives, or say 醒来. Each app is a spiral arm of falling "
                         + "words; tap one to press it on the Mac. Say \"Duerme\" to end the call."),
            TourStep(scene: .chat, spot: "whatsNew", title: "What's new and the time machine",
                     text: "Behind the sparkles: what changed in each release, this tour, and the TIME "
                         + "MACHINE, which can put any earlier version of Arisu on this iPad, back to the "
                         + "first one."),
            TourStep(scene: .chat, spot: "settings", title: "Settings",
                     text: "Her face, the animation's size, glow and pace, free form, and the rest."),
        ]),
        Release(version: "10.0", name: "Singularity", date: "2026-10-02", highlights: [
            Highlight(symbol: "hurricane", name: "Singularity",
                      what: "A full-screen version of Arisu: a black hole in the middle, and every app on the "
                          + "deck a spiral arm whose actions fall into it as words.",
                      how: "Pick SINGULARITY from the menu under the title, or swipe with three fingers. Tap "
                          + "an app at the end of an arm, then one of its words. Tap the centre to mute."),
            Highlight(symbol: "bolt.fill", name: "Waking her",
                      what: "She arrives in two seconds: an implosion, a flash, a shockwave, her name アリス, "
                          + "a deep sound and a line of Old Norse about victory.",
                      how: "Hold anywhere on Singularity, or say 醒来 while she is asleep."),
            Highlight(symbol: "text.bubble", name: "Duerme and Vía",
                      what: "\"Duerme\" ends the call; \"Vía\" ends it and goes back to the classic screen."),
            Highlight(symbol: "circle.dashed", name: "Information rings",
                      what: "Magenta text round the black hole: the next plan block, what is due, days to the "
                          + "race, kilometres this week, habits done."),
            Highlight(symbol: "music.note", name: "She moves with your music",
                      what: "While idle, her animation follows the beat of Spotify on the Mac."),
            Highlight(symbol: "mic.slash", name: "Recording mutes the Mac",
                      what: "The Mac goes silent while you record a brain dump."),
            Highlight(symbol: "sun.max", name: "Her greeting",
                      what: "A new conversation opens with hello and the three things that matter today."),
            Highlight(symbol: "hand.tap", name: "Chat gestures",
                      what: "Double tap for voice, two-finger double tap for a new chat, pull down for history."),
            Highlight(symbol: "square.grid.3x3", name: "The deck follows your apps",
                      what: "Every app has its own keys, the name opens the app, and the keys you use most "
                          + "move to the front."),
            Highlight(symbol: "square.dashed", name: "Free form",
                      what: "No boxes, edges or grid, and her animation breathes behind everything."),
        ]),
        Release(version: "9.0", name: "Command bubbles and the deck wheel", date: "2026-10-01", highlights: [
            Highlight(symbol: "bubble.left.and.text.bubble.right", name: "Command bubbles",
                      what: "Brief, week review, AI signals, what's next and running, one tap each, beside her."),
            Highlight(symbol: "dial.medium", name: "Deck wheel",
                      what: "The deck's groups roll as a wheel under your finger and spring onto one."),
            Highlight(symbol: "waveform.path", name: "Smooth voice visual",
                      what: "Her animation runs smoothly and eases between states; Oscar> and Arisu> on every line."),
        ]),
        Release(version: "8.0", name: "Record and Pencil", date: "2026-10-01", highlights: [
            Highlight(symbol: "record.circle", name: "Record panel",
                      what: "A neon REC panel above the deck for brain dumps, with the look used everywhere."),
            Highlight(symbol: "pencil.tip", name: "Pencil scribbles",
                      what: "The first Pencil touch opens a canvas that saves beside the brain dumps."),
            Highlight(symbol: "link", name: "Links in chat", what: "Web links in her answers can be tapped."),
        ]),
        Release(version: "7.0", name: "Voice visuals", date: "2026-09-29", highlights: [
            Highlight(symbol: "circle.hexagongrid", name: "Her face is a voice visual",
                      what: "Spheres, aurora and flat animations that breathe and move with what she is doing."),
            Highlight(symbol: "slider.horizontal.3", name: "Settings with dials",
                      what: "Size, glow and pace for the animation, and a preview of the face."),
        ]),
        Release(version: "6.0", name: "One screen and the deck", date: "2026-09-28", highlights: [
            Highlight(symbol: "rectangle.split.2x1", name: "One screen",
                      what: "One top bar, the chat first, and the deck beside it under your hand."),
            Highlight(symbol: "square.grid.3x3.fill", name: "The deck",
                      what: "Your Mac's buttons on the iPad, following whatever the Mac is doing."),
        ]),
        Release(version: "5.0", name: "Voice and Chat", date: "2026-09-24", highlights: [
            Highlight(symbol: "terminal", name: "Typed chat",
                      what: "A chat mode of its own, switched with a Voice | Chat toggle."),
            Highlight(symbol: "app.badge", name: "アリス icon", what: "The app gets its own icon."),
            Highlight(symbol: "list.bullet.rectangle", name: "Voice log",
                      what: "Voice calls are recorded in the desk's log, with history and new conversation."),
        ]),
        Release(version: "4.0", name: "Arisu3D", date: "2026-09-23", highlights: [
            Highlight(symbol: "cube", name: "Her 3D model",
                      what: "The remote 3D model is her face, and every version up to V30 is in the list."),
        ]),
        Release(version: "3.0", name: "Live2D and the glow", date: "2026-09-18", highlights: [
            Highlight(symbol: "person.crop.circle", name: "Live2D face", what: "An optional Live2D face from the desk."),
            Highlight(symbol: "light.max", name: "State glow",
                      what: "A glow round her in a colour per state, and the transcript as chat bubbles."),
            Highlight(symbol: "tray", name: "Inbox", what: "She plays the desk's queued lines when you come back."),
        ]),
        Release(version: "2.0", name: "Live face and rooms", date: "2026-09-10", highlights: [
            Highlight(symbol: "face.smiling", name: "Live face",
                      what: "Her face is drawn live and fills the glass; her jaw follows her voice."),
            Highlight(symbol: "person.3", name: "Rooms",
                      what: "More than one character, solo or in a group, with a mute button."),
        ]),
        Release(version: "1.0", name: "On the iPad", date: "2026-09-09", highlights: [
            Highlight(symbol: "ipad", name: "A real iPad app",
                      what: "Barge-in, one question one answer, bigger controls, a settings sheet, a voice "
                          + "in a circle for conversation mode."),
        ]),
        Release(version: "0.1", name: "First form", date: "2026-09-09", highlights: [
            Highlight(symbol: "sparkle", name: "Where it began",
                      what: "The iPhone app made universal for the iPad Pro: her face, a transcript toggle "
                          + "and a start/stop button."),
        ]),
    ]
}

// MARK: - Tour spots

/// Where each named control is on screen, for the tour's cut-out.
struct TourSpots: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Name this view for guided tours. Added to the names inside it rather
    /// than replacing them: a plain anchorPreference hid every spot within a
    /// named view, which is why 11.0's tour lit nothing for the voice button.
    func tourSpot(_ name: String) -> some View {
        transformAnchorPreference(key: TourSpots.self, value: .bounds) { $0[name] = $1 }
    }
}

// MARK: - Tour overlay

/// The whole screen dimmed except one control, with a card saying what it is.
/// A tap anywhere goes on; the card's buttons go back or end it.
struct TourOverlay: View {
    let steps: [TourStep]
    let spots: [String: Anchor<CGRect>]
    @Binding var index: Int
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { geo in
            let step = steps[min(index, steps.count - 1)]
            let hole = step.spot.flatMap { spots[$0] }.map { geo[$0].insetBy(dx: -10, dy: -10) }
            ZStack {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14)) }
                }
                .fill(Color.black.opacity(0.74), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture { next() }
                if let hole {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Skin.mag, lineWidth: 2)
                        .shadow(color: Skin.mag, radius: 10)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)
                }
                card(step)
                    .frame(width: min(520, geo.size.width - 48))
                    .position(cardPoint(hole, in: geo.size))
            }
            .animation(.easeInOut(duration: 0.3), value: index)
        }
        .ignoresSafeArea()
    }

    /// Below the lit control if it is in the top half, above it otherwise,
    /// kept on screen; the middle when nothing is lit. When neither fits --
    /// a tall panel on the iPad held in landscape, where the screen is only
    /// 1032pt high -- beside it, on the wider side, so the card never covers
    /// the thing it is explaining (14.0).
    private func cardPoint(_ hole: CGRect?, in size: CGSize) -> CGPoint {
        guard let hole else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        // ponytail: a fixed guess at the card's size; measure it if long texts start to overlap.
        let cardH: CGFloat = 260, cardW = min(520, size.width - 48)
        let x = min(max(hole.midX, 284), size.width - 284)
        let below = hole.midY < size.height / 2
        let room = below ? size.height - hole.maxY : hole.minY
        let left = hole.minX, right = size.width - hole.maxX
        if room < cardH, max(left, right) >= cardW + 40 {
            let sideX = right >= left ? hole.maxX + 20 + cardW / 2 : hole.minX - 20 - cardW / 2
            return CGPoint(x: sideX, y: min(max(hole.midY, 150), size.height - 150))
        }
        let y = below ? hole.maxY + 120 : hole.minY - 120
        return CGPoint(x: x, y: min(max(y, 130), size.height - 130))
    }

    private func card(_ step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1) / \(steps.count)")
                .font(Skin.mono(11, .medium)).tracking(2).foregroundStyle(Skin.cyan)
            Text(step.title.uppercased())
                .font(Skin.mono(17, .bold)).tracking(2).foregroundStyle(Skin.mag)
            Text(step.text)
                .font(Skin.mono(14)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("SKIP") { onEnd() }.foregroundStyle(Skin.off)
                Spacer()
                if index > 0 { Button("BACK") { index -= 1 }.foregroundStyle(Skin.cyan) }
                Button(index == steps.count - 1 ? "DONE" : "NEXT") { next() }
                    .foregroundStyle(Skin.mag).bold()
            }
            .font(Skin.mono(14, .semibold))
            .padding(.top, 4)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Skin.cyan.opacity(0.7), lineWidth: 1))
        .shadow(color: Skin.cyan.opacity(0.4), radius: 12)
    }

    private func next() {
        if index < steps.count - 1 { index += 1 } else { onEnd() }
    }
}

// MARK: - Demo card

/// The caption of a demo playing: low on the screen so what it describes stays
/// in view, with a bar for the time left on this stop. A tap anywhere else, or
/// STOP, ends the demo and puts everything back.
struct DemoCard: View {
    let steps: [DemoStep]
    let index: Int
    let onStop: () -> Void
    @State private var started = Date()

    var body: some View {
        let step = steps[min(index, steps.count - 1)]
        // Voice mode's bar is along the bottom, and is often the thing being
        // shown: the card goes to the top there.
        let top = step.scene == .voice || step.scene == .glance
        ZStack(alignment: top ? .top : .bottom) {
            // Swallows touches: the screen underneath is being shown, not used,
            // and a tap on Singularity would press one of his Mac's keys.
            Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { onStop() }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("DEMO  \(index + 1) / \(steps.count)")
                        .font(Skin.mono(11, .medium)).tracking(2).foregroundStyle(Skin.cyan)
                    Spacer()
                    Button("STOP") { onStop() }
                        .font(Skin.mono(14, .semibold)).foregroundStyle(Skin.mag)
                }
                Text(step.title.uppercased())
                    .font(Skin.mono(17, .bold)).tracking(2).foregroundStyle(Skin.mag)
                Text(step.text)
                    .font(Skin.mono(14)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: started, by: 0.25)) { tl in
                    let k = min(1, tl.date.timeIntervalSince(started) / step.seconds)
                    GeometryReader { g in
                        Rectangle().fill(Skin.cyan.opacity(0.25))
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Skin.cyan).frame(width: g.size.width * k)
                            }
                    }
                    .frame(height: 2)
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Skin.cyan.opacity(0.7), lineWidth: 1))
            .shadow(color: Skin.cyan.opacity(0.4), radius: 12)
            .padding(.horizontal, 24).padding(top ? .top : .bottom, top ? 90 : 40)
        }
        .onChange(of: index) { _, _ in started = Date() }
        .ignoresSafeArea()
    }
}

// MARK: - Time machine

/// The Mac's time machine, as the app sees it: `GET /deck/travel.json` for
/// every build, `POST /deck/travel` to go to one. The Mac does the building
/// and installing; this app is closed and replaced when it lands.
@MainActor
final class TimeMachine: ObservableObject {
    struct Build: Decodable, Identifiable {
        let sha: String
        let date: String
        let subject: String
        let version: String
        var release: Bool?
        var name: String?
        var notes: String?
        var built: Bool?
        var id: String { sha }
    }
    struct Job: Decodable { let state: String; let detail: String; let sha: String }
    private struct Answer: Decodable { var timeline: [Build]?; let job: Job }

    @Published var builds: [Build] = []
    @Published var job: Job?
    @Published var error: String?

    static let page = DeckAPI.base.appendingPathComponent("deck/travel")
    #if targetEnvironment(simulator)
    private let target = "sim"
    #else
    private let target = "ipad"
    #endif

    var releases: [Build] { builds.filter { $0.release == true } }

    /// The commits after a release and before the next one, oldest last.
    func between(_ release: Build) -> [Build] {
        guard let i = builds.firstIndex(where: { $0.sha == release.sha }) else { return [] }
        return Array(builds[..<i].reversed().prefix { $0.release != true }.reversed())
    }

    func load() async {
        do {
            let (data, _) = try await URLSession.shared.data(
                from: DeckAPI.base.appendingPathComponent("deck/travel.json"))
            let a = try JSONDecoder().decode(Answer.self, from: data)
            builds = a.timeline ?? []
            job = a.job
            error = nil
        } catch {
            self.error = "The Mac's time machine did not answer. Is the Mac awake?"
        }
    }

    func travel(to b: Build) async {
        var r = URLRequest(url: DeckAPI.base.appendingPathComponent("deck/travel"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["sha": b.sha, "target": target])
        _ = try? await URLSession.shared.data(for: r)
        // Poll until it lands -- at which point this app is killed and the
        // other version opens, so the loop simply stops being.
        for _ in 0..<400 {
            await poll()
            if let s = job?.state, s == "failed" || s == "done" { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func poll() async {
        guard let (data, _) = try? await URLSession.shared.data(
            from: URL(string: DeckAPI.base.absoluteString + "deck/travel.json?status=1")!),
              let a = try? JSONDecoder().decode(Answer.self, from: data) else { return }
        job = a.job
    }
}

// MARK: - The sheet behind the sparkles

/// What's new in this release, its tour, and the time machine.
struct ReleasesSheet: View {
    let onTour: () -> Void
    let onDemo: ([DemoStep]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var machine = TimeMachine()
    /// Only ever set from a simulator launch, to check a tab (see ContentView).
    @State private var tab = UserDefaults.standard.integer(forKey: "arisu.sheetTab")
    @State private var going: TimeMachine.Build?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("WHAT'S NEW").tag(0)
                    Text("RELEASES").tag(1)
                    Text("TIME MACHINE").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24).padding(.vertical, 12)
                ScrollView {
                    switch tab {
                    case 0: whatsNew
                    case 1: releases
                    default: timeMachine
                    }
                }
            }
            .background(Grid(tint: Skin.cyan).ignoresSafeArea())
            .navigationTitle("Arisu \(Releases.running) — \(Releases.current.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Skin.cyan)
                }
            }
            .task { await machine.load() }
            .confirmationDialog(going.map { "Travel to \($0.version)?" } ?? "", isPresented: .constant(going != nil),
                                titleVisibility: .visible) {
                Button("Travel to \(going?.version ?? "")") {
                    if let b = going { Task { await machine.travel(to: b) } }
                    going = nil
                }
                Button("Cancel", role: .cancel) { going = nil }
            } message: {
                Text("The Mac builds this version and installs it. Arisu closes and reopens as it. "
                     + "The first trip to a version takes two to four minutes.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                if !Releases.current.tour.isEmpty {
                    bigButton("TAKE THE TOUR", "map") { dismiss(); onTour() }
                }
                if !Releases.current.demo.isEmpty {
                    bigButton("WATCH THE DEMO", "play.rectangle") { dismiss(); onDemo(Releases.current.demo) }
                }
            }
            ForEach(Releases.current.highlights) { highlightRow($0) }
        }
        .padding(24)
    }

    private func bigButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Skin.mono(15, .bold)).tracking(2)
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Skin.mag, lineWidth: 1.5))
                .shadow(color: Skin.mag.opacity(0.6), radius: 8)
        }
        .buttonStyle(.plain)
    }

    private var releases: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Releases.all) { r in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(r.version)  \(r.name.uppercased())")
                            .font(Skin.mono(17, .bold)).tracking(1.5).foregroundStyle(Skin.mag)
                        Text(r.date).font(Skin.mono(12)).foregroundStyle(Skin.off)
                        if r.version == Releases.running { here }
                        Spacer()
                        // An older release's demo plays here too: its features
                        // are still in this build (21.0).
                        if !r.demo.isEmpty {
                            Button { dismiss(); onDemo(r.demo) } label: {
                                Label("DEMO", systemImage: "play.rectangle")
                                    .font(Skin.mono(13, .bold)).tracking(1.5).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Skin.mag, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(r.highlights) { highlightRow($0) }
                }
            }
        }
        .padding(24)
    }

    private var here: some View {
        Text("YOU ARE HERE").font(Skin.mono(11, .bold)).tracking(1.5)
            .foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Skin.cyan)
    }

    private func highlightRow(_ item: Highlight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Skin.cyan)
                .shadow(color: Skin.cyan, radius: 6)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name.uppercased())
                    .font(Skin.mono(15, .bold)).tracking(2).foregroundStyle(.white)
                Text(item.what).font(Skin.mono(14)).foregroundStyle(.white.opacity(0.9))
                if !item.how.isEmpty {
                    Text("> " + item.how)
                        .font(Skin.mono(13)).foregroundStyle(Skin.cyan.opacity(0.85))
                }
            }
        }
    }

    private var timeMachine: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let job = machine.job, ["starting", "building", "installing", "failed"].contains(job.state) {
                Text(job.state == "failed" ? "THE TRIP FAILED\n\(job.detail)"
                     : "\(job.state.uppercased())…  \(job.detail)")
                    .font(Skin.mono(14, .semibold))
                    .foregroundStyle(job.state == "failed" ? Skin.mag : Skin.cyan)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Skin.cyan.opacity(0.6)))
            }
            if let e = machine.error {
                Text(e).font(Skin.mono(14)).foregroundStyle(Skin.mag)
            }
            ForEach(machine.releases) { r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(r.version)  \((r.name ?? "").uppercased())")
                            .font(Skin.mono(16, .bold)).tracking(1.5).foregroundStyle(Skin.mag)
                        Text(String(r.date.prefix(10))).font(Skin.mono(12)).foregroundStyle(Skin.off)
                        if r.version == Releases.running { here }
                        Spacer()
                        travelButton(r, big: true)
                    }
                    if let n = r.notes, !n.isEmpty {
                        Text(n).font(Skin.mono(13)).foregroundStyle(.white.opacity(0.85))
                    }
                    let steps = machine.between(r)
                    if !steps.isEmpty {
                        DisclosureGroup("\(steps.count) builds after it") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(steps) { b in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(b.version).font(Skin.mono(12, .bold)).foregroundStyle(Skin.cyan)
                                            .frame(width: 62, alignment: .leading)
                                        Text(b.subject).font(Skin.mono(12)).foregroundStyle(.white.opacity(0.8))
                                        Spacer()
                                        travelButton(b, big: false)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(Skin.mono(12)).tint(Skin.cyan)
                    }
                }
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Skin.cyan.opacity(0.35)))
            }
            Button {
                openURL(TimeMachine.page)
            } label: {
                Text("Versions before 11.0 cannot come back by themselves. From one of them, open "
                     + "\(TimeMachine.page.absoluteString) in Safari and travel to the newest release.")
                    .font(Skin.mono(12)).foregroundStyle(Skin.cyan.opacity(0.8))
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private func travelButton(_ b: TimeMachine.Build, big: Bool) -> some View {
        Button { going = b } label: {
            Text(b.built == true ? "TRAVEL" : "TRAVEL ⧗")
                .font(Skin.mono(big ? 13 : 11, .bold)).tracking(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, big ? 12 : 8).padding(.vertical, big ? 7 : 3)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Skin.mag, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(["starting", "building", "installing"].contains(machine.job?.state ?? ""))
    }
}
