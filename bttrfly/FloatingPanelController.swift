import SwiftUI
import AppKit
import Combine        // for ObservableObject


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
    @State private var isButtonHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)        // match title color in all themes
                .font(.system(size: 14, weight: .semibold))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(isButtonHovered ? 0.18 : 0))
                )
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isButtonHovered = $0 }
    }
}

// MARK: - Reactive file title view (click-to-edit)
private struct FileTitleView: View {
    @ObservedObject var model: MarkdownModel
    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draft, onCommit: commit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(maxWidth: 140)
                    .onAppear { draft = model.currentFileName }   // 현재 제목 로드
                    .onExitCommand { isEditing = false }          // Esc = 취소
            } else {
                Text(model.currentFileName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .onTapGesture { isEditing = true }            // 클릭 → 편집모드
            }
        }
        .padding(.horizontal, 4)
    }

    /// 편집 확정(⌅/Return) 시 호출
    private func commit() {
        isEditing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }                    // 빈 제목 무시
        model.rename(to: trimmed)                                 // 모델에 rename 요청
    }
}

final class FloatingPanelController: NSWindowController, NSToolbarDelegate {
    weak var model: MarkdownModel?

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
                item.view = NSHostingView(rootView:
                    FileTitleView(model: model))
            }
            return item
            
        case .openFile:
            let item = NSToolbarItem(itemIdentifier: id)
            item.toolTip = "⌘P"
            item.view = NSHostingView(rootView:
                ToolbarButton(systemName: "magnifyingglass",
                              tooltip: "⌘+P",
                              action: { [weak self] in self?.toggleSearchPanel() }))
            item.view?.toolTip = "⌘P"     // ensure tooltip on the custom view itself
            return item

        case .newFile:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSHostingView(rootView:
                ToolbarButton(systemName: "pencil.line",
                              tooltip: "New Note",
                              action: { [weak self] in self?.newDocument() }))
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
