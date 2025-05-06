import Combine
import AppKit
import UniformTypeIdentifiers

final class MarkdownModel: ObservableObject {
    @Published var text: String = ""
    @Published var url: URL?
    private var saveCancellable: AnyCancellable?
    private var securityAccess: Bool = false

    init() {
        // Auto‑save whenever text changes (0.5 s debounce)
        saveCancellable = $text
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                try? self?.save()
            }
    }

    /// Convenience: quick check for .md extension when binding
    static let markdownUTType = UTType(filenameExtension: "md") ?? .plainText

    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    /// Generate a unique URL inside the sandbox container’s Documents/Bttrfly folder.
    private static func autoGenerateURL(for text: String) throws -> URL {
        let baseDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "")
            .appendingPathComponent("Data/Documents/Bttrfly", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        // filename = first line or "Untitled"
        var base = "Untitled"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.split(separator: "\n").first, !first.isEmpty {
            base = String(first.prefix(50))
        }

        // ensure uniqueness
        var candidate = base
        var counter = 0
        var url = baseDir.appendingPathComponent(candidate).appendingPathExtension("md")
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            candidate = "\(base)-\(counter)"
            url = baseDir.appendingPathComponent(candidate).appendingPathExtension("md")
        }
        return url
    }

    // MARK: - Load / Save

    /// Load a local (sandbox) file – existing behaviour preserved
    func load(fileURL: URL) throws {
        try load(fileURL: fileURL, bookmark: nil)
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

        self.text = try String(contentsOf: url!, encoding: .utf8)
        watch(url!)
    }

    func save() throws {
        if !securityAccess, let u = url {
            securityAccess = u.startAccessingSecurityScopedResource()
        }
        if url == nil {
            url = try Self.autoGenerateURL(for: text)
        }
        guard let fileURL = url else { return }
        let data = Data(text.utf8)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - File Watcher
    private func watch(_ url: URL) {
        source?.cancel()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main)

        source?.setEventHandler { [weak self] in
            guard let self, let url = self.url else { return }
            self.text = (try? String(contentsOf: url, encoding: .utf8)) ?? self.text
        }
        source?.setCancelHandler { [fd = fileDescriptor] in close(fd) }
        source?.resume()
    }

    deinit {
        if securityAccess, let u = url {
            u.stopAccessingSecurityScopedResource()
        }
    }
}
