import SwiftUI
import AppKit


extension NSToolbarItem.Identifier {
    static let fileTitle = NSToolbarItem.Identifier("bttrfly.fileTitle")
    static let newFile   = NSToolbarItem.Identifier("bttrfly.newFile")
    static let openFile  = NSToolbarItem.Identifier("bttrfly.openFile")
}

// MARK: - Toolbar button with hover highlight
private struct ToolbarButton: View {
    let systemName: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)        // match title color in all themes
                .font(.system(size: 14, weight: .semibold))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(isHovered ? 0.18 : 0))
                )
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Reactive file title view
private struct FileTitleView: View {
    @ObservedObject var model: MarkdownModel
    var body: some View {
        Text(model.currentFileName)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }
}

final class FloatingPanelController: NSWindowController, NSToolbarDelegate {
    private weak var model: MarkdownModel?

    convenience init(root: some View, model: MarkdownModel) {
        let panel = NSPanel(
            contentRect: .init(x: 0, y: 0, width: 400, height: 550),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        self.init(window: panel)

        self.model = model

        panel.contentView = NSHostingView(rootView: root)

        // ── Toolbar setup ───────────────────────────────
        let tb = NSToolbar(identifier: "NoteToolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        tb.centeredItemIdentifier = .fileTitle
        panel.toolbar = tb
        panel.toolbarStyle = .unifiedCompact
        // ────────────────────────────────────────────────

        // Position at bottom‑right
        if let screen = NSScreen.main {
            let margin: CGFloat = 24
            let frame = panel.frame
            let x = screen.visibleFrame.maxX - frame.width - margin
            let y = screen.visibleFrame.minY + margin
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ tb: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .fileTitle, .flexibleSpace, .openFile, .newFile]
    }
    func toolbarAllowedItemIdentifiers(_ tb: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .fileTitle, .newFile, .openFile]
    }

    func toolbar(_ tb: NSToolbar,
                 itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        switch id {
        case .fileTitle:
            let item = NSToolbarItem(itemIdentifier: id)
            if let model = model {
                item.view = NSHostingView(rootView: FileTitleView(model: model))
            }
            return item
            
        case .openFile:
            let item = NSToolbarItem(itemIdentifier: id)
            item.toolTip = "⌘P"
            item.view = NSHostingView(rootView:
                ToolbarButton(systemName: "magnifyingglass",
                              tooltip: "⌘+P",
                              action: { [weak self] in self?.toggleSearchPanel() })
            )
            item.view?.toolTip = "⌘P"     // ensure tooltip on the custom view itself
            return item

        case .newFile:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSHostingView(rootView:
                ToolbarButton(systemName: "pencil.line",
                              tooltip: "New Note",
                              action: { [weak self] in self?.newDocument() })
            )
            return item



        default: return nil
        }
    }

    // MARK: - Actions
    @objc func newDocument() {
        model?.createNewFile()
    }
    @objc private func openDocument() {
        model?.presentOpenPanel()
    }
    @objc private func toggleSearchPanel() {
        SearchPanelController.shared.toggle(relativeTo: window)
    }
}
