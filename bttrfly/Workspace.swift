import Foundation

/// Legacy workspace class retained only to satisfy existing references.
/// All storage is handled directly in `MarkdownModel`.
final class Workspace {
    static let shared = Workspace()
    private init() {}
}
