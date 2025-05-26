//
//  QuickOpenView.swift
//  bttrfly
//
//  Created by William Jung on 5/17/25.
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// MVP for Quick‑Open: choose a vault folder, then list all .md files.
/// Search/filter will come next.
struct QuickOpenView: View {
    @ObservedObject var model: MarkdownModel
    @AppStorage("showDefaultFolder") private var showDefaultFolder = true

    // MARK: - State
    @State private var vaultURL: URL? = nil
    @State private var files: [URL] = []
    @State private var recent: [URL] = loadRecent()
    @State private var query = ""
    @State private var selection: URL? = nil          // keyboard selection
    @FocusState private var listFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverDropdown = false
    @State private var pinned: [URL] = loadPinnedFolders()
    @State private var hoverAdd = false
    @State private var dragging: URL? = nil      // current item being dragged
    @State private var keyMonitor: Any? = nil    // local NSEvent monitor for ⏎ key
    @State private var scrollProxy: ScrollViewProxy? = nil   // NEW
    // Track which row the mouse is currently over
    @State private var hovered: URL? = nil

    /// User‑specified default save folder (nil until the user picks one)
    private var coreFolder: URL? { model.loadSavedFolderURL() }

    var body: some View {
        VStack(spacing: 12) {

            // ── Search bar with vault dropdown ────────────────
            HStack(spacing: 6) {
                Button(action: pickFile) {
                    Image(systemName: "book.pages")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.secondary.opacity(hoverDropdown ? 0.18 : 0))
                        )
                        .frame(width: 24, height: 24)
                        .help("Open Markdown File…")
                }
                .buttonStyle(.plain)
                .onHover { hoverDropdown = $0 }

                TextField("Search for notes…", text: $query)
                    .textFieldStyle(.plain)
                    .padding(4)
                    .layoutPriority(1)
            }

            // ── Pinned folders ─────────────────────────────
            if true {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pinned, id: \.self) { url in
                            PinnedFolderChip(
                                url: url,
                                isSelected: vaultURL == url,
                                dragging: $dragging,
                                coreFolder: coreFolder,
                                select: { selected in
                                    // Keep security scope open (idempotent if already active)
                                    _ = selected.startAccessingSecurityScopedResource()

                                    // Switch vault & refresh file list
                                    vaultURL = selected
                                    files = scanMarkdown(in: selected)
                                    query = ""       // clear filter

                                    // Just highlight first note (for convenience); user can double‑click or press ⏎ to open
                                    selection = files.first
                                },
                                remove: { removed in
                                    removePinned(removed)
                                })
                            // ── Drag to re‑order ─────────────────────────────
                            .onDrag {
                                dragging = url               // remember source
                                return NSItemProvider(object: url as NSURL)   // use file‑URL UTType
                            }
                            .onDrop(of: [UTType.fileURL.identifier],
                                    delegate: FolderReorderDropDelegate(item: url,
                                                                        items: $pinned,
                                                                        dragging: $dragging,
                                                                        save: { savePinnedFolders($0) }))
                        }
                        // Add new folder button
                        Button(action: pickAndPin) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.secondary.opacity(hoverAdd ? 0.18 : 0.08))
                                )
                                .animation(.easeInOut(duration: 0.08), value: hoverAdd)
                        }
                        .buttonStyle(.plain)
                        .onHover { hoverAdd = $0 }
                        .help("Add folder to Favorites")
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)   // extra headroom for delete button
                }
            }

            // ── Notes list ──────────────────────────────────
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(displayed, id: \.self) { url in
                        NoteRow(url: url,
                                isCurrent: false,
                                isSelected: selection == url,
                                isHovered: hovered == url)          // NEW
                            .onHover { inside in                   // update global hover
                                hovered = inside ? url : nil
                            }
                            .contentShape(Rectangle())
                            .tag(url)
                            .id(url)                      // enable scrollTo
                            .listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .accentColor(.clear)
                .scrollContentBackground(.hidden)
                .background(
                    ListGridStyler().allowsHitTesting(false)
                )
                .focused($listFocused)
                .background(DoubleClickHandler(current: $selection, open: model.open))
                .onAppear {
                    // save proxy and focus list on initial show
                    scrollProxy = proxy
                    if selection == nil { selection = displayed.first }
                    DispatchQueue.main.async { listFocused = true }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didLiveScrollNotification)) { _ in
                    hovered = nil
                }
                .onDisappear {
                    pinned.forEach { $0.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .onAppear {
            // Sync pinned array with preference
            if let core = coreFolder {
                if !showDefaultFolder {
                    pinned.removeAll { $0 == core }
                } else if !pinned.contains(core) {
                    pinned.insert(core, at: 0)
                }
            }
            print("🪵 QuickOpenView sees →", model.debugID)

            // ⏎ / Enter opens the currently‑selected note, all other keys go through
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
                switch ev.keyCode {
                case 36, 76:            // ⏎ / Enter
                    if let responder = NSApp.keyWindow?.firstResponder,
                       responder.isKind(of: NSTableView.self),
                       let url = selection {
                        model.open(url: url)
                        return nil       // consume Enter
                    }
                default:
                    break               // let all other keys (↑/↓ 포함) reach NSTableView
                }
                return ev
            }
        }
        .onChange(of: showDefaultFolder) { on in
            if let core = coreFolder {
                if on {
                    if !pinned.contains(core) {
                        pinned.insert(core, at: 0)
                        savePinnedFolders(pinned)
                    }
                } else {
                    removePinned(core)
                }
            }
        }
        .onDisappear {
            // remove key monitor if still active
            if let m = keyMonitor {
                NSEvent.removeMonitor(m)
                keyMonitor = nil
            }
        }
        // Clear hover highlight whenever keyboard changes selection
        .onChange(of: selection) { _ in
            hovered = nil
        }
        .frame(height: 320)                         // allow width to flex with parent
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .ignoresSafeArea(.container, edges: .top)   // let content extend into the title‑bar area
        // ⌘1–⌘9 → jump to that pinned folder
        .onReceive(NotificationCenter.default.publisher(for: .OpenPinned)) { note in
            guard let idx = note.object as? Int,
                  idx < pinned.count else { return }
            let folder = pinned[idx]

            // keep security scope open; idempotent if already active
            _ = folder.startAccessingSecurityScopedResource()

            vaultURL = folder
            files = scanMarkdown(in: folder)
            // highlight first file & give list keyboard focus
            selection = displayed.first
            DispatchQueue.main.async { listFocused = true }
        }
    }

    // MARK: - Helpers
    /// List actually shown in the UI – recent or vault, then filtered by `query`
    private var displayed: [URL] {
        let base = vaultURL == nil ? recent : files
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        // Simple case‑insensitive filename match
        return base.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
        }
    }

// MARK: - Helpers
    /// Pick a single Markdown file and open it in the editor
    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["md", "markdown"]
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            model.open(url: url)                 // open in main editor
        }
    }

    // Favourites – pick any folder and pin it
    private func pickAndPin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        if panel.runModal() == .OK, let url = panel.url {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if !pinned.contains(url) {
                pinned.append(url)                    // keep in-memory list
                savePinnedFolders(pinned)             // save bookmark data
            }
            // open this folder immediately
            vaultURL = url
            files = scanMarkdown(in: url)
        }
    }

    private func removePinned(_ url: URL) {
        pinned.removeAll { $0 == url }
        savePinnedFolders(pinned)
    }

    private func scanMarkdown(in folder: URL) -> [URL] {
        guard FileManager.default.isReadableFile(atPath: folder.path) else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // Keyboard navigation
    private func moveSelection(_ delta: Int) {
        guard !displayed.isEmpty else { return }

        // 1. Calculate the next index within bounds
        let currentIdx = selection.flatMap { displayed.firstIndex(of: $0) } ?? 0
        let newIdx = min(max(currentIdx + delta, 0), displayed.count - 1)
        let target = displayed[newIdx]

        // 2. Apply new selection
        selection = target
        hovered = nil     // reset hover; will update on next real mouse move

        // 3. Ensure the row is visible – scroll *slightly* past edge so it never hides
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                // If moving down, pin near bottom; if up, near top.
                let anchor: UnitPoint = delta > 0 ? .bottom : .top
                scrollProxy?.scrollTo(target, anchor: anchor)
            }
        }
    }
}

// MARK: - Drag‑&‑drop re‑order support
private struct FolderReorderDropDelegate: DropDelegate {
    let item: URL                 // destination chip
    @Binding var items: [URL]     // pinned array binding
    @Binding var dragging: URL?   // currently dragged chip
    let save: ([URL]) -> Void     // persist order

    func dropEntered(info: DropInfo) {
        guard let dragging = dragging, dragging != item else { return }

        if let from = items.firstIndex(of: dragging),
           let to = items.firstIndex(of: item) {
            withAnimation {
                items.move(fromOffsets: IndexSet(integer: from),
                           toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        save(items)       // persist new order
        dragging = nil
        return true
    }
}

// MARK: - Pinned folder chip
private struct PinnedFolderChip: View {
    let url: URL
    let isSelected: Bool
    @Binding var dragging: URL?
    let coreFolder: URL?
    let select: (URL) -> Void
    let remove: (URL) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false
    @AppStorage("showDefaultFolder") private var showDefaultFolder = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main chip tap == select folder
            Label(url.lastPathComponent, systemImage: "folder")
                .font(.caption2)                      // slightly smaller
                .foregroundColor(
                    isSelected ? Color.primary :
                        (hover ? Color.secondary : Color.secondary.opacity(0.65))
                )
                .padding(.vertical, 6)    // taller
                .padding(.horizontal, 10)  // wider side padding
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            Color.secondary
                                .opacity(hover ? 0.18 : 0.08)
                        )
                )
                .animation(.easeInOut(duration: 0.08), value: hover)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { select(url) }

            // ── Hover delete ("x") button ──
            if hover && !(url == coreFolder && showDefaultFolder) {
                Button(action: { remove(url) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(scheme == .dark ? Color.black : Color.white)   // icon colour inverted for contrast
                        .padding(3)
                        .background(
                            Circle()
                                .fill(Color.secondary)   // use secondary colour in all themes
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -4)    // just outside the chip
            }
        }
        .opacity(dragging == url ? 0 : 1)   // hide original while dragging
        .onHover { hover = $0 }
        .help(url.path)      // show absolute path on hover
    }
}

struct NoteRow: View {
    var url: URL
    var isCurrent: Bool
    var isSelected: Bool
    var isHovered: Bool         // NEW

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(isCurrent ? Color.red : Color.clear)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)
                Text("\(modifiedDateString(url)) • \(characterCount(url)) Characters")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 6))   // reduce left gap
        .listRowBackground(
            (isSelected || isHovered)
            ? Color(nsColor: NSColor.controlAccentColor)
                .opacity(isSelected ? 0.18 : 0.08)
            : Color.black.opacity(0.01)
        )
    }

    private func characterCount(_ url: URL) -> Int {
        (try? String(contentsOf: url).count) ?? 0
    }
    
    private func modifiedDateString(_ url: URL) -> String {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let date = attrs[.modificationDate] as? Date
        else { return "—" }

        let fmt = DateFormatter()
        fmt.dateStyle = .medium   // 예: May 18, 2025
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }
}

// MARK: - Simple recent + favourites storage
private func loadRecent() -> [URL] {
    (UserDefaults.standard.array(forKey: "recentFiles") as? [String] ?? [])
        .compactMap { URL(fileURLWithPath: $0) }
        .prefix(5)
        .map { $0 }
}

private func saveRecentVault(_ url: URL) {
    UserDefaults.standard.set([url.path], forKey: "recentVault")
}

// Favourites (persistent, security‑scoped bookmarks)

/// Load favourites from stored security‑scoped bookmarks, then deduplicate while preserving order.
private func loadPinnedFolders() -> [URL] {
    // 1) Resolve saved bookmarks
    let datas = UserDefaults.standard.array(forKey: "pinnedBookmarks") as? [Data] ?? []
    var urls: [URL] = []
    for data in datas {
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale),
           !isStale,
           url.startAccessingSecurityScopedResource() {
            urls.append(url)
        }
    }

    // 2) Deduplicate by standardized, case‑folded path while preserving order
    var seen = Set<String>()
    var unique: [URL] = []
    for url in urls {
        let key = url.standardizedFileURL.path.lowercased()
        if !seen.contains(key) {
            unique.append(url)
            seen.insert(key)
        }
    }
    return unique
}

/// Persist user‑pinned folders.
private func savePinnedFolders(_ urls: [URL]) {
    let datas: [Data] = urls.compactMap {
        try? $0.bookmarkData(options: [.withSecurityScope],
                             includingResourceValuesForKeys: nil,
                             relativeTo: nil)
    }
    UserDefaults.standard.set(datas, forKey: "pinnedBookmarks")
}


// MARK: - Style / hide NSTableView grid lines
private struct ListGridStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let table = locateTable(in: nsView) else { return }
        table.gridStyleMask = []                 // no grid lines
        table.gridColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.style = .fullWidth
        table.intercellSpacing = NSSize(width: 0, height: 0)  // no thin gaps
    }

    private func locateTable(in view: NSView) -> NSTableView? {
        if let t = view as? NSTableView { return t }
        for sub in view.subviews {
            if let t = locateTable(in: sub) { return t }
        }
        return nil
    }
}


// MARK: - NSTableView double‑click support
private struct DoubleClickHandler: NSViewRepresentable {
    @Binding var current: URL?
    let open: (URL) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async {            // wait until List is in the hierarchy
            guard let table = locateTable(starting: v) else { return }
            // Preserve original single‑click target once
            if context.coordinator.originalTarget == nil {
                context.coordinator.originalTarget = table.target as AnyObject
            }

            // Route actions through Coordinator
            table.target = context.coordinator
            table.action = #selector(Coordinator.onAction(_:))          // single click
            table.doubleAction = #selector(Coordinator.didDoubleClick(_:)) // double click
            context.coordinator.current = $current
            context.coordinator.open = open
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var current: Binding<URL?> = .constant(nil)
        var open: (URL) -> Void = { _ in }
        weak var originalTarget: AnyObject?   // SwiftUI가 설치한 원래 타깃

        /// 싱글‑클릭 전달용: SwiftUI 쪽 selection 업데이트 유지
        @objc func onAction(_ sender: Any?) {
            guard let orig = originalTarget else { return }
            let sel = Selector(("onAction:"))
            if orig.responds(to: sel) {
                _ = orig.perform(sel, with: sender)
            }
        }

        @objc func didDoubleClick(_ sender: Any?) {
            if let url = current.wrappedValue { open(url) }
        }
    }

    // ── Find the nearest NSTableView (ascend first, then descend) ──
    private func locateTable(starting view: NSView?) -> NSTableView? {
        var node = view
        while let current = node {
            if let t = searchDown(current) { return t }   // look inside
            node = current.superview                     // climb up
        }
        return nil
    }

    /// Depth‑first search **down** the subtree rooted at `view`
    private func searchDown(_ view: NSView) -> NSTableView? {
        if let t = view as? NSTableView { return t }
        for sub in view.subviews {
            if let t = searchDown(sub) { return t }
        }
        return nil
    }
}



