import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

// MARK: - MarkdownModel
// Simple observable model that loads/saves a markdown file.
final class MarkdownModel: ObservableObject {
    @Published var text: String = ""
    @Published var url: URL?
    private var saveCancellable: AnyCancellable?

    init() {
        // Auto‑save whenever text changes (0.5 s debounce)
        saveCancellable = $text
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                try? self?.save()
            }
    }
    
    /// Convenience: quick check for .md extension when binding
    static let markdownUTType = UTType(filenameExtension: "md") ?? .plainText

    func load(fileURL: URL) throws {
        text = try String(contentsOf: fileURL, encoding: .utf8)
        url  = fileURL
    }

    func save() throws {
        guard let url else { return }
        guard url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileWriteNoPermission)
        }
        defer { url.stopAccessingSecurityScopedResource() }

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
        // Enable Web Inspector for debugging
        web.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
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

        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            // Swift -> JS: observe model.text changes
            cancellable = parent.model.$text
                .dropFirst()
                .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                .sink { [weak self] md in
                    guard let webView = self?.web else { return }
                    let escaped = md.replacingOccurrences(of: "`", with: "\\`")
                    webView.evaluateJavaScript("""
                        window.editor?.commands.setContent(`\(escaped)`);
                    """, completionHandler: nil)
                }
        }

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
