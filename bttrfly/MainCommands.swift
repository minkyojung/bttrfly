import SwiftUI

struct MainCommands: Commands {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate: AppDelegate   // delegate 접근

    var body: some Commands {
        CommandGroup(after: .newItem) {   // inject into the existing "File" menu
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
    }
}
