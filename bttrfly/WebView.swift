import SwiftUI
import WebKit
import Combine

// MARK: - MarkdownModel
// Simple observable model that loads/saves a markdown file.
final class MarkdownModel: ObservableObject {
    @Published var text: String = ""
    @Published var url: URL?

    func load(fileURL: URL) throws {
        text = try String(contentsOf: fileURL, encoding: .utf8)
        url  = fileURL
    }

    func save() throws {
        guard let url else { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct WebView: NSViewRepresentable {
    @ObservedObject var model: MarkdownModel

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "didChange")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        // Load local EditorResources/index.html
        if let htmlURL = Bundle.main.url(forResource: "index",
                                         withExtension: "html",
                                         subdirectory: "EditorResources") {
            web.loadFileURL(htmlURL,
                            allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            print("❌ index.html not found in bundle")
        }
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // update view as needed
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        // JS -> Swift: receive HTML updates
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let html = message.body as? String else { return }
            DispatchQueue.main.async {
                self.parent.model.text = html
            }
        }

        // Optional: handle didFinish to inject Swift -> JS later
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let escaped = parent.model.text
                .replacingOccurrences(of: "`", with: "\\`")   // JS 백틱 이스케이프
            webView.evaluateJavaScript("window.editor?.commands.setContent(`\(escaped)`);")
        }
        
        
    }
}
