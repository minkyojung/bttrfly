//
//  bttrflyApp.swift
//  bttrfly
//
//  Created by William Jung on 4/27/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct MyFloatingMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // A hidden settings scene is enough to satisfy SwiftUI’s requirement
        // for at least one `Scene`, while avoiding an empty window opening.
        Settings {
            EmptyView()          // nothing visible
        }
        .commands {
            MainCommands()       // ✅ your “Open…” / “Save…” items
        }
    }
    
    
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanelController?
    let model = MarkdownModel()
    private var autosave: AutosaveService?

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = FloatingPanelController(root: WebView(model: model))
        panel?.showWindow(nil)
        autosave = AutosaveService(model: model)
        print("Documents path 👉",
              FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Documents").path)
    }

    @objc func openDocument(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            // Create a security‑scoped bookmark
            guard let bm = try? url.bookmarkData(options: .withSecurityScope,
                                                 includingResourceValuesForKeys: nil,
                                                 relativeTo: nil) else { return }
            // Save to recent list
            RecentFileManager.shared.add(url: url, bookmark: bm)
            // Load into model (model handles scope)
            try? model.load(fileURL: url, bookmark: bm)
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        do {
            try model.save()
        } catch {
            print("❌ Failed to save markdown file:", error)
        }
    }
}
