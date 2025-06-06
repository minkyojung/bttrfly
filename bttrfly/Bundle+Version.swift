import Foundation

extension Bundle {
    /// CFBundleShortVersionString, fallback "0"
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
