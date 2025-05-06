import Foundation
import AppKit
import Combine
@available(*, deprecated, message: "Replaced by Workspace singleton")
final class LegacyWorkspace: ObservableObject {
    private let key = "WorkingDirBookmark"
    @Published private(set) var currentFolder: URL?

    private init() { restoreBookmark() }

    // 처음·재실행 시 호출
    func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        if let u = try? URL(resolvingBookmarkData: data,
                            options: [.withSecurityScope],
                            bookmarkDataIsStale: &stale),
           u.startAccessingSecurityScopedResource() {
            currentFolder = u
        }
    }

    // 메뉴에서 호출
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        panel.begin { [self] resp in
            guard resp == .OK, let dir = panel.url else { return }
            if let bm = try? dir.bookmarkData(options: .withSecurityScope,
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil) {
                UserDefaults.standard.set(bm, forKey: key)
                dir.startAccessingSecurityScopedResource()
                currentFolder = dir               // 🔔 바인딩용
            }
        }
    }
}
