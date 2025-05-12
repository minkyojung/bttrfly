import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

struct WebView: NSViewRepresentable {
    @ObservedObject var model: MarkdownModel

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "didChange")
        let web = WKWebView(frame: .zero, configuration: cfg)
        // Enable Web Inspector for debugging
        web.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        web.navigationDelegate = context.coordinator
        // Make the WKWebView transparent so it sits directly on the blur layer
        web.setValue(false, forKey: "drawsBackground")   // disable white background
        if let scrollView = web.enclosingScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
        // Load local EditorResources/index.html
        if let htmlURL = Bundle.main.url(forResource: "index",
                                         withExtension: "html",
                                         subdirectory: "EditorResources") {
            web.loadFileURL(htmlURL,
                            allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            print("❌ index.html not found in bundle")
        }
        context.coordinator.web = web   // keep reference for Swift → JS updates
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // update view as needed
    }
    
    

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
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
                .dropFirst()
                .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                .sink { [weak self] md in
                    guard let self = self,
                          !self.isUpdatingFromJS,
                          md != self.lastHTMLFromJS,
                          let webView = self.web else { return }
                    let escaped = md.replacingOccurrences(of: "`", with: "\\`")
                    webView.evaluateJavaScript("""
                        window.editor?.commands.setContent(`\(escaped)`);
                    """, completionHandler: nil)
                }
        }

        // JS -> Swift: receive HTML updates
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            print("➡️ onUpdate", Date().timeIntervalSince1970)
            guard let html = message.body as? String else { return }
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
        
        
    }
}
