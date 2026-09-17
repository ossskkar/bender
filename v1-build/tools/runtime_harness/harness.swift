import Cocoa
import WebKit
let a = CommandLine.arguments; let url = a[1]; let outDir = a[2]
class D: NSObject, WKScriptMessageHandler {
  func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
    guard let o = m.body as? [String: Any], let t = o["type"] as? String else { return }
    if t == "log" { print(o["text"] as? String ?? ""); fflush(stdout) }
    if t == "png", let n = o["name"] as? String, let s = o["data"] as? String, let d = Data(base64Encoded: String(s.split(separator: ",")[1])) {
      try? d.write(to: URL(fileURLWithPath: outDir + "/" + n.replacingOccurrences(of: "+", with: "_") + ".png")) }
    if t == "done" { exit(0) }
  }
}
let app = NSApplication.shared; let cfg = WKWebViewConfiguration(); let d = D()
cfg.userContentController.add(d, name: "log")
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
let wv = WKWebView(frame: win.contentView!.bounds, configuration: cfg); win.contentView!.addSubview(wv); win.orderFront(nil)
wv.load(URLRequest(url: URL(string: url)!))
DispatchQueue.main.asyncAfter(deadline: .now() + 240) { print("TIMEOUT"); exit(2) }
app.run()
