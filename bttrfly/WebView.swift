import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers
import AppKit            // for NSWorkspace.open(_: )

struct WebView: NSViewRepresentable {
    @ObservedObject var model: MarkdownModel

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "didChange")
        cfg.userContentController.add(context.coordinator, name: "openLink")
        cfg.userContentController.add(context.coordinator, name: "saveNote")
        cfg.userContentController.add(context.coordinator, name: "installUpdate")
        // Allow local scripts and modules to load from file:// URLs (macOS 13+)
        if let prefs = cfg.preferences as? NSObject {
            prefs.setValue(true, forKey: "allowFileAccessFromFileURLs")
        }
        let web = WKWebView(frame: .zero, configuration: cfg)
        // Enable Web Inspector for debugging
        web.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator        // handle target=_blank links
        // Make the WKWebView transparent so it sits directly on the blur layer
        web.setValue(false, forKey: "drawsBackground")   // disable white background
        if let scrollView = web.enclosingScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
        // Load the editor's index.html (prefer the dist build, fall back to root)
        if let htmlURL = Bundle.main.url(forResource: "index",
                                         withExtension: "html",
                                         subdirectory: "dist") {

            web.loadFileURL(htmlURL,
                            allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            print("❌ index.html not found – check Copy Bundle Resources.")
        }
        context.coordinator.web = web   // keep reference for Swift → JS updates
        (NSApp.delegate as? AppDelegate)?.webView = web
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // update view as needed
    }
    
    

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        var web: WKWebView?
        private var cancellable: AnyCancellable?
        private var isUpdatingFromJS = false
        private var lastHTMLFromJS = ""

        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            // Swift -> JS: observe model.text changes
            cancellable = parent.model.$text
                .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                .sink { [weak self] md in
                    guard let self = self,
                          !self.isUpdatingFromJS,
                          md != self.lastHTMLFromJS,
                          let webView = self.web else { return }

                    // Keep local copy in sync so we don't resend identical HTML later
                    self.lastHTMLFromJS = md

                    // If the incoming Markdown/HTML string is empty, clear the editor;
                    // otherwise, replace its contents.
                    let js: String
                    if md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        js = "window.editor?.commands.clearContent();"
                    } else {
                        let escaped = md
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "`", with: "\\`")
                            .replacingOccurrences(of: "\n", with: "\\n")
                        js = "window.editor?.commands.setContent(`\(escaped)`);"
                    }
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
        }

        // JS -> Swift: receive HTML updates and openLink
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {

            if message.name == "openLink",
               let urlString = message.body as? String,
               let url = URL(string: urlString) {
                print("[Swift] got openLink →", url.absoluteString)
                let ok = NSWorkspace.shared.open(url)
                print("[Swift] NSWorkspace.open returned", ok)
                return
            }
            else if message.name == "installUpdate" {
                print("[Swift] installUpdate requested from JS")
                (NSApp.delegate as? AppDelegate)?
                    .updater?.checkForUpdates()
                return
            }
            else if message.name == "saveNote",
                    let markdown = message.body as? String {
                print("🔖 saveNote received – \(markdown.count) chars")
                // TODO: persist markdown to model or disk
                return
            }

            // default: didChange markdown text
            guard message.name == "didChange",
                  let html = message.body as? String else { return }

            DispatchQueue.main.async {
                self.isUpdatingFromJS = true
                self.lastHTMLFromJS = html
                self.parent.model.text = html
                // keep flag true for one more runloop so Combine sink is skipped
                DispatchQueue.main.async { self.isUpdatingFromJS = false }
            }
        }

        // Optional: handle didFinish to inject Swift -> JS later
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let escaped = parent.model.text
                .replacingOccurrences(of: "`", with: "\\`")   // JS 백틱 이스케이프
            webView.evaluateJavaScript("window.editor?.commands.setContent(`\(escaped)`);")
            webView.becomeFirstResponder()   // make WKWebView the key responder
            webView.evaluateJavaScript("window.editor?.commands.focus();")   // focus the tiptap editor
        }
        
        // macOS: open any external http/https link in the default browser
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            // If the target frame is nil → means window.open / target=_blank
            let isLinkClick = navigationAction.navigationType == .linkActivated
            let isNewWindow  = navigationAction.targetFrame == nil

            if (isLinkClick || isNewWindow),
               let url = navigationAction.request.url,
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {

                print("[Swift] decidePolicyFor link →", url.absoluteString)
                let ok = NSWorkspace.shared.open(url)
                print("[Swift] NSWorkspace.open returned", ok)
                decisionHandler(.cancel)   // don't load internally
                return
            }
            decisionHandler(.allow)
        }
        
        // WKUIDelegate – handle target="_blank" or window.open links
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            print("[Swift] createWebViewWith for target=_blank →", navigationAction.request.url?.absoluteString ?? "nil")
            if let url = navigationAction.request.url {
                let ok = NSWorkspace.shared.open(url)
                print("[Swift] NSWorkspace.open returned", ok)
            }
            return nil        // cancel creation of a new WKWebView
        }
        
        
    }
}
