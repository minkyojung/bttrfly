import SwiftUI
import KeyboardShortcuts

// 단축키 레코더 UI
struct ShortcutPrefs: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Note Shortcut",
                                       name: .showNote)
        }
        .padding(20)
        .frame(width: 300)
    }
}

// UserDefaults 키 정의
extension KeyboardShortcuts.Name {
    static let showNote = Self("showNote")
}
