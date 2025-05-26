import SwiftUI

struct MainCommands: Commands {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate: AppDelegate   // delegate 접근
    
    var body: some Commands {
        // Replace default “New” (⌘N) with our custom new‑note action
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                delegate.panel?.newDocument()
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        
        CommandGroup(after: .newItem) {   // inject into the existing "File" menu
            Divider()
            Button("Show Notes Folder") {
                // If the user has selected a custom save folder, open that.
                if let folder = delegate.panel?.model?.saveFolder {
                    NSWorkspace.shared.open(folder)
                } else {
                    // Fallback to legacy sandbox‑container path
                    let baseDir = FileManager.default
                        .homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Containers")
                        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "")
                        .appendingPathComponent("Data/Documents/Bttrfly", isDirectory: true)
                    try? FileManager.default.createDirectory(at: baseDir,
                                                             withIntermediateDirectories: true)
                    NSWorkspace.shared.open(baseDir)
                }
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
