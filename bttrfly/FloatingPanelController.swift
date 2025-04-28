import SwiftUI

final class FloatingPanelController: NSWindowController {
    convenience init(root: some View) {
        let panel = NSPanel(
            contentRect: .init(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        self.init(window: panel)
        panel.contentView = NSHostingView(rootView: root)
    }
}
