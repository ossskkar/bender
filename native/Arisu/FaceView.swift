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
    /// The glow around her silhouette, as "r,g,b" in 0...255. How it behaves
    /// is the state's business, in `glowCSS`.
    var glow = "69,230,247"
    /// How the Live2D spotlight is tuned. Ignored by the portrait.
    var tune = Persona.Glow()

    /// A drop-shadow on the page body follows the canvas alpha, so the glow is
    /// her outline rather than a disc behind her, and it works for the
    /// portrait and the Live2D page alike without either page knowing.
    /// Idle is dim and still, listening steady, thinking a slow pulse,
    /// speaking follows `--amp`. Asleep has none. It also hides the Live2D
    /// page's test buttons for good: `showPanel(false)` runs before
    /// `window.avatar` exists on a slow load, and the bar stayed up.
    fileprivate static let glowCSS = """
    #arisu-harness{display:none!important}
    body{transition:filter .35s ease}
    body[data-glow=idle]{filter:drop-shadow(0 0 6px rgba(var(--halo),.15))}
    body[data-glow=listening]{filter:drop-shadow(0 0 10px rgba(var(--halo),.35))}
    body[data-glow=thinking]{animation:arisu-pulse 1.8s ease-in-out infinite}
    body[data-glow=speaking]{transition:none;filter:drop-shadow(0 0 calc(6px + 10px * var(--amp,0)) rgba(var(--halo),calc(.2 + .35 * var(--amp,0))))}
    @keyframes arisu-pulse{0%,100%{filter:drop-shadow(0 0 5px rgba(var(--halo),.1))}50%{filter:drop-shadow(0 0 14px rgba(var(--halo),.4))}}
    """

    /// Which Live2D sample each character wears by default. Mirrors the first
    /// entry of `LIVE2D_MODELS` in lain's `arisu/index.html`; a character with
    /// no model keeps its portrait.
    private static let live2dModel = ["arisu": "Haru", "chopper": "Natori"]
    /// Every sample lain ships, mirroring `ALL_MODELS` in `arisu/index.html`.
    static let models = ["Haru", "Hiyori", "Mao", "Rice", "Natori", "Ren", "Mark", "Wanko"]
    private static let allModels = Set(models)

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
        private var sentGlow: String?
        private var sentTune: Persona.Glow?
        fileprivate var sentAmplitude = -1.0
        private var lastAmplitudeAt = Date.distantPast
        weak var web: WKWebView?

        func webView(_ web: WKWebView, didFinish _: WKNavigation!) {
            loaded = true
            // The Live2D page shows its test buttons when it is not framed, and
            // here it is the top page. The portrait has no such member.
            web.evaluateJavaScript(
                "window.avatar && window.avatar.showPanel && window.avatar.showPanel(false)")
            let css = FaceView.glowCSS.replacingOccurrences(of: "\n", with: " ")
            web.evaluateJavaScript("""
                var st=document.createElement('style');st.textContent='\(css)';\
                document.head.appendChild(st)
                """)
            // Whatever arrived while the page was still parsing.
            if let t = sentTune { sentTune = nil; apply(tune: t) }
            if let g = sentGlow { sentGlow = nil; apply(glow: g) }
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
            sentGlow = nil
            sentTune = nil
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
            web.evaluateJavaScript("document.body.dataset.glow='\(state)';" +
                                   "window.avatar && window.avatar.setState('\(state)')")
            spotlight()
        }

        func apply(glow: String) {
            guard glow != sentGlow else { return }
            sentGlow = glow
            guard loaded, let web else { return }
            web.evaluateJavaScript("document.body.style.setProperty('--halo','\(glow)')")
            spotlight()
        }

        func apply(tune: Persona.Glow) {
            guard tune != sentTune else { return }
            sentTune = tune
            spotlight()
        }

        /// The Live2D page stands her in an opaque room, which hides the
        /// drop-shadow glow. It has its own light between the room and the
        /// model, a spotlight behind her, so the state colour goes there.
        /// Peaks mirror lain's `cues.js`. The portrait has no `ArisuScene`.
        private func spotlight() {
            guard loaded, let web, let state = sentState, let glow = sentGlow else { return }
            let t = sentTune ?? Persona.Glow()
            let base = ["idle": 0.55, "listening": 0.7, "thinking": 1.0,
                        "speaking": 0.95][state] ?? 0.4
            // Defaults and the cap at 1 mirror `resolveGlow` in cues.js.
            let peak = min(1, base * (t.strength ?? 1.5))
            web.evaluateJavaScript(
                "window.ArisuScene && ArisuScene.setGlow({state:'\(state)',colour:'\(glow)'," +
                "glow:\(peak),size:\(t.size ?? 1.3),x:\(t.x ?? 54),y:\(t.y ?? 42)})")
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
                "document.body.style.setProperty('--amp','\(String(format: "%.3f", amplitude))');" +
                "window.avatar && window.avatar.setAmplitude(\(String(format: "%.3f", amplitude)));" +
                "window.ArisuScene && ArisuScene.setGlow({loud:\(String(format: "%.2f", amplitude * 0.85))})")
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
        context.coordinator.apply(tune: tune)
        context.coordinator.apply(glow: glow)
        context.coordinator.apply(state: state)
        context.coordinator.apply(amplitude: amplitude)
    }
}
