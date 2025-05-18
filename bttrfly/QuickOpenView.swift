//
//  QuickOpenView.swift
//  bttrfly
//
//  Created by William Jung on 5/17/25.
//

import SwiftUI
import AppKit
import Combine

/// MVP for Quick‑Open: choose a vault folder, then list all .md files.
/// Search/filter will come next.
struct QuickOpenView: View {
    @ObservedObject var model: MarkdownModel

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

    var body: some View {
        VStack(spacing: 12) {

            // ── Search bar with vault dropdown ────────────────
            HStack(spacing: 6) {
                Button(action: pickVault) {
                    Image(systemName: "folder")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.secondary.opacity(hoverDropdown ? 0.18 : 0))
                        )
                        .frame(width: 24, height: 24)
                        .help(vaultURL == nil ? "Choose Folder" : "Change Folder")
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
                                select: { selected in
                                    _ = selected.startAccessingSecurityScopedResource() // (idempotent if already open)
                                    vaultURL = selected
                                    files = scanMarkdown(in: selected)
                                    model.open(url: selected)
                                },
                                remove: { removed in
                                    removePinned(removed)
                                })
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
            List(selection: $selection) {
                            ForEach(displayed, id: \.self) { url in
                                // ⏎(Enter) = defaultAction → 파일 열기
                                Button(action: {
                                    model.open(url: url)
                                    print("🪵 QuickOpen opening", url.lastPathComponent, "on model", model.debugID)
                                }) {
                                    NoteRow(url: url,
                                            isCurrent: false,
                                            isSelected: selection == url)
                                }
                                .buttonStyle(.plain)                 // 시각적 변화 없도록
                                .keyboardShortcut(.defaultAction)    // Return/Enter 트리거
                                .tag(url)
                                .listRowInsets(EdgeInsets())
                            }
                        }
            .listStyle(.plain)
            .listRowSeparator(.hidden)   // hide default separator (macOS 14+)
            .accentColor(.clear)         // suppress system green selection tint
            .scrollContentBackground(.hidden)
            .background(
                ListGridStyler().allowsHitTesting(false) // remove NSTableView grid + spacing
            )
            .focused($listFocused)
            // 🔹 첫 표시 때만: 첫 행 하이라이트 + 리스트 포커스
                        .onAppear {
                            if selection == nil { selection = displayed.first }
                            DispatchQueue.main.async { listFocused = true }
                        }
                        
            .onDisappear {
                pinned.forEach { $0.stopAccessingSecurityScopedResource() }
            }
        }
        .onAppear {
            print("🪵 QuickOpenView sees →", model.debugID)
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

    private func pickVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            vaultURL = url
            files = scanMarkdown(in: url)
            saveRecentVault(url)
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
}

// MARK: - Pinned folder chip
private struct PinnedFolderChip: View {
    let url: URL
    let isSelected: Bool
    let select: (URL) -> Void
    let remove: (URL) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main chip tap == select folder
            Button(action: { select(url) }) {
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
            }
            .buttonStyle(.plain)

            // ── Hover delete ("x") button ──
            if hover {
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
        .onHover { hover = $0 }
    }
}

struct NoteRow: View {
    var url: URL
    var isCurrent: Bool
    var isSelected: Bool
    @State private var hover = false

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
            (isSelected || hover)
            ? Color(nsColor: NSColor.controlAccentColor)
                .opacity(isSelected ? 0.18 : 0.08)
            : Color.clear
        )
        .onHover { hover = $0 }
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
private func loadPinnedFolders() -> [URL] {
    let datas = UserDefaults.standard.array(forKey: "pinnedBookmarks") as? [Data] ?? []
    var urls: [URL] = []

    for data in datas {
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale),
           !isStale
        {
            if url.startAccessingSecurityScopedResource() {   // keep it open
                urls.append(url)
            }
        }
    }
    return urls
}

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
