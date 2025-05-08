import SwiftUI

final class FloatingPanelController: NSWindowController {
    convenience init(root: some View) {
        let panel = NSPanel(
            contentRect: .init(x: 0, y: 0, width: 400, height: 550),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver    // always‑on‑top, even above other floating windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // Make the window itself a clear, single‑layer “glass” sheet
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true        // keep the standard macOS shadow
        self.init(window: panel)
        panel.contentView = NSHostingView(rootView: root)
        
        // Position the panel at the bottom‑right corner of the primary screen
        if let screen = NSScreen.main {
            let margin: CGFloat = 24
            let frame = panel.frame
            let x = screen.visibleFrame.maxX - frame.width - margin
            let y = screen.visibleFrame.minY + margin
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
