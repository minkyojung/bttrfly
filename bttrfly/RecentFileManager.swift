import Foundation

struct RecentFile: Codable, Equatable {
    let url: URL
    let bookmark: Data
    let openedAt: Date
}

final class RecentFileManager: ObservableObject {
    static let shared = RecentFileManager()
    private init() { load() }

    @Published private(set) var files: [RecentFile] = []

    private let key = "BttrflyRecentFiles"
    private let limit = 5

    // MARK: – Public API
    func add(url: URL, bookmark: Data) {
        // 중복 제거
        files.removeAll { $0.url == url }
        files.insert(RecentFile(url: url, bookmark: bookmark, openedAt: .now), at: 0)
        // 개수 제한
        if files.count > limit { files.removeLast(files.count - limit) }
        save()
    }

    func bookmark(for url: URL) -> Data? {
        files.first { $0.url == url }?.bookmark
    }

    // MARK: – Persistence
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) else { return }
        files = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(files) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
