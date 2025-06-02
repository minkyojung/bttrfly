import Combine
import AppKit
import UniformTypeIdentifiers
import Mixpanel

final class MarkdownModel: ObservableObject {
    /// Global shared instance – the *only* MarkdownModel in the app
    static let shared = MarkdownModel()
    let debugID = UUID()           // 디버그용 식별자
    @Published var text: String = ""
    @Published var url: URL?
    @Published var currentFileName: String = "Untitled"
    /// true = note created in-app, false = opened existing file
    @Published var isScratch: Bool = true
    private var saveCancellable: AnyCancellable?
    /// Keeps the window title synced with the first 20 characters of the note
    private var titleCancellable: AnyCancellable?
    private var securityAccess: Bool = false
    /// Folder chosen in onboarding; *single* source of truth for the whole app.
    @Published var saveFolder: URL? {
        didSet {
            print("🪵 saveFolder didSet →", saveFolder?.path ?? "nil")
            guard let folder = saveFolder else { return }
            // ⓐ Persist security‑scoped bookmark (overwrite if exists)
            saveBookmark(for: folder)
            // ⓑ Persist plain‑URL for legacy / convenience
            UserDefaults.standard.set(folder, forKey: "bttrflySaveFolder")
        }
    }
    


    // MARK: - Focus‑time tracking
    private var sessionStart: Date?
    private var focusSeconds: Int {
        get { UserDefaults.standard.integer(forKey: "statsFocusSeconds") }
        set { UserDefaults.standard.set(newValue, forKey: "statsFocusSeconds") }
    }

    private init() {
        // Restore folder from bookmark (preferred) or plain URL
        if let restored = loadSavedFolderURL() ??
                          UserDefaults.standard.url(forKey: "bttrflySaveFolder") {
            saveFolder = restored
        }
        // Auto‑save whenever text changes (0.5 s debounce)
        print("🪵 MarkdownModel init →", debugID)
        saveCancellable = $text
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                try? self?.save()
            }
        // Live‑update the window title while typing (scratch notes only)
        titleCancellable = $text
            .receive(on: RunLoop.main)     // UI updates must occur on main thread
            .sink { [weak self] value in
                guard let self = self, self.isScratch else { return }

                let firstLine = Self.firstNonEmptyLine(in: value)
                let candidate = firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(20))

                if self.currentFileName != candidate {
                    self.currentFileName = candidate
                }
            }
    }

    // MARK: - Session helpers
    /// Call when a note becomes active
    func startSession() {
        sessionStart = Date()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "statsSessionStart")
    }

    /// Call before switching/closing note to accumulate focus seconds
    func endSession() {
        guard let start = sessionStart else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        focusSeconds += elapsed

        // 🔔 Mixpanel: 집중 세션 종료
        let origin: String
        if isScratch {
            origin = "internal"
        } else if let core = saveFolder,
                  !(url?.path.hasPrefix(core.path) ?? true) {
            origin = "external"
        } else {
            origin = "internal"
        }
        Mixpanel.mainInstance().track(event: "focus_session_end",
                                      properties: ["noteId": debugID.uuidString,
                                                   "durationSec": elapsed,
                                                   "origin": origin])

        UserDefaults.standard.removeObject(forKey: "statsSessionStart")
        UserDefaults.standard.set(focusSeconds, forKey: "statsFocusSeconds")   // ensure persisted
        sessionStart = nil
    }

    /// Sanitize a string so it can be used safely as a macOS filename.
    private static func safeFilename(from raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalid).joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Return the first non‑empty line from a string (after trimming whitespace).
    private static func firstNonEmptyLine(in text: String) -> String {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { return line }
        }
        return ""
    }

    /// Return a .md URL that is unique inside `dir`, adding -1, -2 … if needed.
    private static func uniqueURL(for base: String, in dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var candidate = base
        var counter   = 0
        var url       = dir.appendingPathComponent(candidate).appendingPathExtension("md")
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            candidate = "\(base)-\(counter)"
            url = dir.appendingPathComponent(candidate).appendingPathExtension("md")
        }
        return url
    }

    // MARK: - Public helper ------------------------------------------------
    /// Open an existing Markdown file (inside or outside the sandbox).
    /// Convenience wrapper so callers don’t need to care about bookmarks.
    @MainActor
    func open(url: URL) {
        endSession()
        print("🪵 open() called for", url.lastPathComponent, "on model", debugID)
        // Re‑use existing loader; ignore errors silently for now
        try? load(fileURL: url)
        
        // 🔔 Mixpanel: 외부 노트 열기
            if let core = saveFolder, !url.path.hasPrefix(core.path) {
                Mixpanel.mainInstance().track(event: "open_external_note",
                                              properties: ["noteId": url.lastPathComponent,
                                                           "folderPath": url.deletingLastPathComponent().path])
            }
        
        startSession()
    }

    /// Convenience: quick check for .md extension when binding
    static let markdownUTType = UTType(filenameExtension: "md") ?? .plainText

    /// Generate a unique URL in the user's home directory.
    private static func autoGenerateURL(for text: String) throws -> URL {
        let model = MarkdownModel.shared
        guard let baseDir = model.loadSavedFolderURL() else {
            throw NSError(domain: "NoSavedFolderURL", code: 0, userInfo: nil)
        }
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        // filename base = sanitized first line (max 20 chars) or "Untitled"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? ""
        let rawBase = firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(20))
        var base = safeFilename(from: rawBase)

        // ensure uniqueness
        var candidate = base
        var counter = 0
        var url = baseDir.appendingPathComponent(candidate).appendingPathExtension("md")
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            candidate = "\(base)-\(counter)"
            url = baseDir.appendingPathComponent(candidate).appendingPathExtension("md")
        }
        print("📂 Will save to: \(url.path)")
        return url
    }
    

    // MARK: - Load / Save

    /// Load a local (sandbox) file – existing behaviour preserved
    func load(fileURL: URL) throws {
        try load(fileURL: fileURL, bookmark: nil)
        isScratch = false
    }

    /// Load an external file using an optional security‑scoped bookmark.
    func load(fileURL: URL, bookmark: Data?) throws {
        // If a bookmark is provided, resolve & start security scope
        if let bm = bookmark {
            var stale = false
            let scoped = try URL(resolvingBookmarkData: bm,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale)
            securityAccess = scoped.startAccessingSecurityScopedResource()
            self.url = scoped
        } else {
            self.url = fileURL           // internal file – sandbox already allows write
        }
        isScratch = false

        self.text = try String(contentsOf: url!, encoding: .utf8)
        self.currentFileName = String(url!.lastPathComponent.prefix(20))
    }

    func save() throws {
        let firstSave = (url == nil)
        
        print("💾 save() start — current url:", url?.path ?? "nil",
              " | saveFolder:", saveFolder?.path ?? "nil")
        // Ensure a save folder exists before writing
        guard let saveFolder else { throw ModelError.noFolder }

        if !securityAccess, let u = url {
            securityAccess = u.startAccessingSecurityScopedResource()
        }
        // ── Decide target filename based on first line ──
        let firstLine = Self.firstNonEmptyLine(in: text)
        let rawBase   = firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(20))

        if url == nil {
            // 첫 저장
            url = try Self.uniqueURL(for: rawBase, in: saveFolder)
        } else if isScratch {
            // 현재 파일 이름(숫자 꼬리 제거)
            let currentBase = url!.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "-\\d+$",
                                      with: "",
                                      options: .regularExpression)

            // 제목이 실제로 달라졌을 때만 rename
            if currentBase != rawBase {
                let newURL = try Self.uniqueURL(for: rawBase, in: saveFolder)
                try? FileManager.default.moveItem(at: url!, to: newURL)
                url = newURL
            }
        }
        guard let fileURL = url else { return }
        let data = Data(text.utf8)
        try data.write(to: fileURL, options: .atomic)
        
        // 🔔 Mixpanel: 첫 저장
        if firstSave {
               Mixpanel.mainInstance().track(event: "first_save",
                                             properties: ["noteId": debugID.uuidString,
                                                          "chars": text.count])
           }
        
        updateStats()
    }


    deinit {
        endSession()
        if securityAccess, let u = url {
            u.stopAccessingSecurityScopedResource()
        }
        titleCancellable?.cancel()
    }

    // MARK: - Rename

    /// Rename the current note (and underlying file, if it already exists).
    /// - Parameter newTitle: Raw user input; will be sanitised and trimmed.
    func rename(to newTitle: String) {
        // ① Sanitise and limit to 20 characters
        let safeBase = String(Self.safeFilename(from: newTitle).prefix(20))
        guard !safeBase.isEmpty, safeBase != currentFileName else { return }

        // ② If a file exists, actually rename it on disk
        if let oldURL = url {
            let folder = oldURL.deletingLastPathComponent()
            if let newURL = try? Self.uniqueURL(for: safeBase, in: folder) {
                var scoped = securityAccess
                if !scoped { scoped = oldURL.startAccessingSecurityScopedResource() }
                defer { if scoped { oldURL.stopAccessingSecurityScopedResource() } }

                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                url = newURL
            }
        }

        // ③ Update in‑memory title; save() will handle further consistency
        currentFileName = safeBase
    }

    // MARK: - Toolbar helpers
    func createNewFile() {
        endSession()

        // ── End security‑scoped access ──
        if securityAccess, let u = url {
            u.stopAccessingSecurityScopedResource()
        }
        securityAccess = false

        // ── Reset model state for a fresh scratch note ──
        url = nil
        text = ""
        currentFileName = "Untitled"
        isScratch = true
        startSession()
        
        Mixpanel.mainInstance().track(event: "create_note",
                                          properties: ["noteId": debugID.uuidString])
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.markdownUTType]
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            try? self?.load(fileURL: url)
        }
    }
    
    @MainActor
    func chooseSaveFolder(completion: @escaping (URL?) -> Void) {
        print("🐛 chooseSaveFolder on main? –", Thread.isMainThread)
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.chooseSaveFolder(completion: completion)
            }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        panel.begin { [weak self] result in
            guard let self = self else { completion(nil); return }

            if result == .OK, let folderURL = panel.url {
                print("✅ picked folder →", folderURL.path)
                // ── Release security scope on old file before switching folders ──
                if self.securityAccess, let old = self.url {
                    old.stopAccessingSecurityScopedResource()
                    self.securityAccess = false
                }

                _ = folderURL.startAccessingSecurityScopedResource()
                // self.saveBookmark(for: folderURL)   // now handled in saveFolder's didSet
                self.saveFolder = folderURL
                // UserDefaults.standard.set(folderURL, forKey: "bttrflySaveFolder")   // legacy path key (now handled in saveFolder's didSet)
                self.updateStats()
                completion(folderURL)
            } else {
                completion(nil)
            }
        }
    }

    /// Save security-scoped bookmark to UserDefaults
    func saveBookmark(for folder: URL) {
        do {
            let bookmark = try folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: "SavedFolderBookmark")
        } catch {
            print("❌ Failed to save bookmark:", error)
        }
    }

    /// Load saved bookmark from UserDefaults
    func loadSavedFolderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "SavedFolderBookmark") else { return nil }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if url.startAccessingSecurityScopedResource() {
                return url
            }
        } catch {
            print("❌ Failed to load bookmark:", error)
        }
        return nil
    }

    // MARK: - Stats -----------------------------------------------------------
    /// Recalculate total note count and character count in the save folder,
    /// then persist the values to UserDefaults so they can be shown in Settings.
    private func updateStats() {
        guard let folder = saveFolder else { return }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return }

        let mdFiles = files.filter { $0.pathExtension.lowercased() == "md" }

        let noteCount = mdFiles.count
        let charCount = mdFiles.reduce(0) { total, url in
            total + ((try? String(contentsOf: url).count) ?? 0)
        }
        // completed todos: - [x] or - [X]
        let todoDone = mdFiles.reduce(0) { total, url in
            total + ((try? String(contentsOf: url)
                        .components(separatedBy: .newlines)
                        .filter { $0.contains("- [x]") || $0.contains("- [X]") }
                        .count) ?? 0)
        }
        let ud = UserDefaults.standard
        ud.set(noteCount, forKey: "statsNoteCount")
        ud.set(charCount, forKey: "statsCharCount")
        ud.set(todoDone, forKey: "statsTodoDone")
    }
}

enum ModelError: Error {
    /// Attempted to write when `saveFolder` is nil.
    case noFolder
}

