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

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanelController(root: WebView(model: model))
        panel?.showWindow(nil)
    }

    @objc func openDocument(_ sender: Any?) {
        // 패널이 non‑activating일 때도 단축키·메뉴가 동작하도록 앱을 활성화
        NSApp.activate(ignoringOtherApps: true)
        print("💡 openDocument fired")
        let open = NSOpenPanel()
        open.allowedContentTypes = [UTType(importedAs: "net.daringfireball.markdown")]
        open.begin { [weak self] response in
            guard response == .OK, let url = open.url else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            do {
                try self?.model.load(fileURL: url)
            } catch {
                print("Failed to load markdown file:", error)
            }
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
