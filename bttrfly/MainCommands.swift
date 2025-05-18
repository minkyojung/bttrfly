import SwiftUI

struct MainCommands: Commands {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate: AppDelegate   // delegate 접근
    
    var body: some Commands {
        CommandGroup(after: .newItem) {   // inject into the existing "File" menu
            Divider()
            Button("Show Storage Folder") {
                // Path: ~/Library/Containers/<bundle-id>/Data/Documents/Btt
                
                let baseDir = FileManager.default
                    .homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Containers")
                    .appendingPathComponent(Bundle.main.bundleIdentifier ?? "")
                    .appendingPathComponent("Data/Documents/Bttrfly", isDirectory: true)
                try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(baseDir)  // open directly in Finder
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            
            
            Button("Open…") {
                delegate.openDocument(nil)
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            Button("Save…") {
                delegate.saveDocument(nil)
            }
            .keyboardShortcut("s", modifiers: .command)
        }
        
        // Quick‑Open (⌘P) — replaces default “Print…”
        CommandGroup(replacing: .printItem) {
            Button("Quick Open…") {
                if let keyWin = NSApp.keyWindow {
                    SearchPanelController.shared.toggle(relativeTo: keyWin)
                } else {
                    SearchPanelController.shared.toggle(relativeTo: nil)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
        }
    }
    
}
