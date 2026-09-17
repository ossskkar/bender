import Cocoa
import WebKit
// usage: shot <url> <out.png> <wait seconds> [js run after load]
let a = CommandLine.arguments
let url = a[1], out = a[2], wait = Double(a[3])!, js = a.count > 4 ? a[4] : ""
class D: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) { print("console:", m.body) }
  func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if !js.isEmpty { w.evaluateJavaScript(js) { r, e in if let e { print("js error", e) } } } }
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
      w.evaluateJavaScript("JSON.stringify(window.__log||[])") { r, _ in print("log:", r ?? "") }
      w.takeSnapshot(with: nil) { img, e in
        let rep = NSBitmapImageRep(data: img!.tiffRepresentation!)!
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out)); exit(0) }
    }
  }
}
let app = NSApplication.shared
let cfg = WKWebViewConfiguration(); let d = D()
cfg.userContentController.add(d, name: "log")
cfg.userContentController.addUserScript(WKUserScript(source: "window.__log=[];addEventListener('error',e=>__log.push(String(e.message)));window.addEventListener('message',e=>__log.push(JSON.stringify(e.data)));const _e=console.error;console.error=(...x)=>{__log.push(x.join(' '));_e(...x)};const _w=console.warn;console.warn=(...x)=>{__log.push('W '+x.join(' '));_w(...x)}", injectionTime: .atDocumentStart, forMainFrameOnly: true))
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
let wv = WKWebView(frame: win.contentView!.bounds, configuration: cfg); wv.navigationDelegate = d; wv.setValue(false, forKey: "drawsBackground")
win.contentView!.addSubview(wv); win.orderFront(nil)
wv.load(URLRequest(url: URL(string: url)!))
app.run()
