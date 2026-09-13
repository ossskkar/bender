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
///
/// The Live2D face is the same contract from a different page, and it is
/// loaded from the desk rather than the bundle. Decided 2026-09-13 while Oscar
/// was away: the Live2D page carries Cubism Core, whose licence does not allow
/// it in this public repo, and the app already cannot talk without the desk,
/// so loading the face from there adds no dependency it did not have. If the
/// desk cannot be reached the portrait comes back instead of a blank screen.
struct FaceView: UIViewRepresentable {
    /// Which face page to draw, from the active character. A character can
    /// exist on the desk before its portrait has been built, so an id with no
    /// page falls back rather than showing nothing.
    let face: String
    /// One of idle, listening, thinking, speaking, asleep.
    let state: String
    /// Her voice, 0...1. Drives the jaw and the glow at her mouth.
    let amplitude: Double
    /// Draw the Live2D model from the desk instead of the bundled portrait.
    var live2d = false
    /// The character's saved Live2D sample, from the desk. Empty, or a name
    /// this build does not know, falls back to the character's default.
    var model = ""

    /// Which Live2D sample each character wears by default. Mirrors the first
    /// entry of `LIVE2D_MODELS` in lain's `arisu/index.html`; a character with
    /// no model keeps its portrait.
    private static let live2dModel = ["arisu": "Haru", "chopper": "Natori"]
    /// Every sample lain ships, mirroring `ALL_MODELS` in `arisu/index.html`.
    private static let allModels: Set<String> =
        ["Haru", "Hiyori", "Mao", "Rice", "Natori", "Ren", "Mark", "Wanko"]

    /// The page for a character, or the fallback. `arisu` is the fallback
    /// because hers is the portrait the renderer was authored against, so it
    /// is the one face guaranteed to be in the bundle.
    fileprivate static func portrait(for face: String) -> URL? {
        Bundle.main.url(forResource: face, withExtension: "html", subdirectory: "Face")
            ?? Bundle.main.url(forResource: "arisu", withExtension: "html", subdirectory: "Face")
    }

    private static func url(for face: String, live2d: Bool, model saved: String) -> URL? {
        let chosen = allModels.contains(saved) ? saved : live2dModel[face]
        guard live2d, let model = chosen else { return portrait(for: face) }
        var parts = URLComponents(url: Brain.base.appendingPathComponent("live2d/index.html"),
                                  resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "model", value: model)]
        return parts?.url ?? portrait(for: face)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loaded = false
        /// Which page is in the view. A character switch reloads it, and the
        /// state has to be re-sent afterwards -- the new page starts idle and
        /// knows nothing of the conversation it is joining.
        var shown: String?
        /// The character behind the page, for falling back to its portrait.
        private var shownFace = "arisu"
        private var sentState: String?
        fileprivate var sentAmplitude = -1.0
        private var lastAmplitudeAt = Date.distantPast
        weak var web: WKWebView?

        func webView(_ web: WKWebView, didFinish _: WKNavigation!) {
            loaded = true
            // The Live2D page shows its test buttons when it is not framed, and
            // here it is the top page. The portrait has no such member.
            web.evaluateJavaScript(
                "window.avatar && window.avatar.showPanel && window.avatar.showPanel(false)")
            // Whatever arrived while the page was still parsing.
            if let s = sentState { sentState = nil; apply(state: s) }
        }

        func webView(_ web: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            fallBack()
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                     withError _: Error) {
            fallBack()
        }

        /// The desk did not serve the Live2D page. Her portrait is always in the
        /// bundle, and a face beats an empty hologram.
        private func fallBack() {
            guard let key = shown, key.hasPrefix("live2d:"),
                  let url = FaceView.portrait(for: shownFace) else { return }
            show(shownFace, key: shownFace, url: url)
        }

        /// Put a different character on screen. Everything the old page knew
        /// goes with it, so the sent values reset or the first update after a
        /// switch would be skipped as unchanged and the new face would sit
        /// there idle through a conversation.
        func show(_ face: String, key: String, url: URL?) {
            guard key != shown, let url, let web else { return }
            shown = key
            shownFace = face
            loaded = false
            sentState = nil
            sentAmplitude = -1
            if url.isFileURL {
                web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                    timeoutInterval: 15))
            }
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

    /// Which page this view wants, as a key: a mode switch has to reload even
    /// though the character did not change.
    private var key: String { live2d ? "live2d:\(face):\(model)" : face }

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

        context.coordinator.show(face, key: key,
                                 url: FaceView.url(for: face, live2d: live2d, model: model))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.show(face, key: key,
                                 url: FaceView.url(for: face, live2d: live2d, model: model))
        context.coordinator.apply(state: state)
        context.coordinator.apply(amplitude: amplitude)
    }
}
