//
//  bttrflyApp.swift
//  bttrfly
//
//  Created by William Jung on 4/27/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts

@main
struct MyFloatingMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // A hidden settings scene is enough to satisfy SwiftUI’s requirement
        // for at least one `Scene`, while avoiding an empty window opening.
        Settings {
            TabView {
                ShortcutPrefs()
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }

                GeneralPrefs()
                    .tabItem { Label("General", systemImage: "gearshape") }
            }
            .frame(width: 420, height: 240)
        }
        .commands {
            MainCommands()
        }
    }
    
    
}

struct GeneralPrefs: View {
    @AppStorage("showDefaultFolder") private var showDefaultFolder = true
    var body: some View {
        Form {
            Toggle("Show Bttrfly folder in Favorites", isOn: $showDefaultFolder)
        }
        .padding(20)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanelController?
    let model = MarkdownModel()
    private var autosave: AutosaveService?

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = FloatingPanelController(root: NoteView(model: model), model: model)
        panel?.showWindow(nil)
        // Share the same MarkdownModel with the global Search panel
        SearchPanelController.shared.configure(model: model)
        autosave = AutosaveService(model: model)
        print("Documents path 👉",
              FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Documents").path)

        // Register global shortcut
        KeyboardShortcuts.onKeyUp(for: .showNote) { [weak self] in
            self?.toggleNote()
        }
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
    // Toggle the floating note window via global shortcut
    private func toggleNote() {
        guard let panel = panel else { return }
        if panel.window?.isVisible == true {
            panel.close()
        } else {
            panel.showWindow(nil)
            panel.window?.makeKey()        // bring to front
        }
    }
}
