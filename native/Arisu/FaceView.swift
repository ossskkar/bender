import SwiftUI
import WebKit

/// Her face: a canvas renderer in `Face/face.html`, hosted in a web view.
///
/// It replaced three stacked PNGs. Those were a still with a drift animation
/// on two colour-split copies -- convincing from the sofa, and completely
/// unresponsive. This one has five states of its own, blinks on its own timer,
/// drifts its gaze, breathes, and stretches a jaw band with whatever amplitude
/// it is handed, so she looks like she is doing the thing she is doing.
///
/// A web view for a face is a real cost and worth naming: a second rendering
/// engine in the process, and JavaScript between her state and her expression.
/// It buys the renderer exactly as authored, with no port to keep in sync. If
/// the battery says otherwise later, the algorithm is a dithered palette over a
/// contour pass and would go into a Metal shader without much argument.
struct FaceView: UIViewRepresentable {
    /// Which face page to draw, from the active character. A character can
    /// exist on the desk before its portrait has been built, so an id with no
    /// page falls back rather than showing nothing.
    let face: String
    /// One of idle, listening, thinking, speaking, asleep.
    let state: String
    /// Her voice, 0...1. Drives the jaw and the glow at her mouth.
    let amplitude: Double

    /// The page for a character, or the fallback. `arisu` is the fallback
    /// because hers is the portrait the renderer was authored against, so it
    /// is the one face guaranteed to be in the bundle.
    private static func url(for face: String) -> URL? {
        Bundle.main.url(forResource: face, withExtension: "html", subdirectory: "Face")
            ?? Bundle.main.url(forResource: "arisu", withExtension: "html", subdirectory: "Face")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loaded = false
        /// Which page is in the view. A character switch reloads it, and the
        /// state has to be re-sent afterwards -- the new page starts idle and
        /// knows nothing of the conversation it is joining.
        var shown: String?
        private var sentState: String?
        fileprivate var sentAmplitude = -1.0
        private var lastAmplitudeAt = Date.distantPast
        weak var web: WKWebView?

        func webView(_ web: WKWebView, didFinish _: WKNavigation!) {
            loaded = true
            // Whatever arrived while the page was still parsing.
            if let s = sentState { sentState = nil; apply(state: s) }
        }

        /// Put a different character on screen. Everything the old page knew
        /// goes with it, so the sent values reset or the first update after a
        /// switch would be skipped as unchanged and the new face would sit
        /// there idle through a conversation.
        func show(_ face: String, url: URL?) {
            guard face != shown, let url, let web else { return }
            shown = face
            loaded = false
            sentState = nil
            sentAmplitude = -1
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func apply(state: String) {
            guard state != sentState else { return }
            sentState = state
            guard loaded, let web else { return }
            web.evaluateJavaScript("window.avatar && window.avatar.setState('\(state)')")
        }

        /// The level publishes far faster than a face can show, so this sends
        /// on a change worth seeing or every 50ms, whichever is rarer. Without
        /// the throttle this crossed into JavaScript on every frame of the
        /// meter, which is most of what a web view costs.
        func apply(amplitude: Double) {
            guard loaded, let web else { return }
            let now = Date()
            let moved = abs(amplitude - sentAmplitude) > 0.02
            let stale = now.timeIntervalSince(lastAmplitudeAt) > 0.05
            guard moved, stale else { return }
            sentAmplitude = amplitude
            lastAmplitudeAt = now
            web.evaluateJavaScript(
                "window.avatar && window.avatar.setAmplitude(\(String(format: "%.3f", amplitude)))")
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)

        // The hologram raster writes alpha 0 wherever there is no signal, so
        // everything behind her -- the ground that carries her state colour --
        // shows through. An opaque web view would put a black plate over it.
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        // She is scenery, not a control. The buttons live behind her.
        web.isUserInteractionEnabled = false
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web

        context.coordinator.show(face, url: FaceView.url(for: face))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.show(face, url: FaceView.url(for: face))
        context.coordinator.apply(state: state)
        context.coordinator.apply(amplitude: amplitude)
    }
}
