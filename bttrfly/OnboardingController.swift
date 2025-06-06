
import AppKit
import SwiftUI
import QuartzCore


extension Notification.Name {
    static let bttrflyDidPickFolder = Notification.Name("bttrflyDidPickFolder")
}

final class OnboardingController {
    private var window: NSWindow?
    private weak var parent: NSWindow?     // parent to overlay
    private let model: MarkdownModel
    private let hasOnboardedKey = "bttrflyHasOnboarded"
    private let lastSeenKey     = "bttrflyLastSeenVersion"
    private let currentVersion  = Bundle.main.shortVersion

    init(model: MarkdownModel) { self.model = model }

    /// 앱 부팅 시 호출
    func presentIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasOnboardedKey) else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 550),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 28
        panel.contentView?.layer?.masksToBounds = true

        let host = NSHostingController(rootView: OnboardingView(
            pickFolder: { [weak self] in
                guard let self else { return }
                // Hop onto the Main actor asynchronously to satisfy isolation
                Task { @MainActor in
                    self.pickFolder()
                }
            }))
        panel.contentView = host.view
        panel.center()

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        fade(panel, visible: true)
    }

    /// Presents onboarding as a child‑window overlay on top of `parent`.
    func present(over parent: NSWindow) {
        // Already shown once?
        if UserDefaults.standard.bool(forKey: hasOnboardedKey) { return }

        self.parent = parent

        // Match parent window’s frame & style
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 650),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar          // one step above normal
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 28
        panel.contentView?.layer?.masksToBounds = true

        let host = NSHostingController(rootView: OnboardingView(
            pickFolder: { [weak self] in
                guard let self else { return }
                // Hop onto the Main actor asynchronously to satisfy isolation
                Task { @MainActor in
                    self.pickFolder()
                }
            }))
        panel.contentView = host.view

        // Attach as child so it stays in sync with parent position
        parent.addChildWindow(panel, ordered: .above)

        self.window = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        fade(panel, visible: true)
    }

    // MARK: Helpers
    @MainActor
    private func pickFolder() {
        // Keep a strong reference so we can restore it if user cancels
        guard let onboardingWin = self.window else { return }

        // Hide the onboarding panel before showing Finder’s picker
        onboardingWin.orderOut(nil)

        model.chooseSaveFolder { [weak self] url in
            guard let self else { return }

            if let url {        // ✅ Folder chosen
                // Persist chosen folder and inject into model
                UserDefaults.standard.set(url, forKey: "bttrflySaveFolder")
                self.model.saveFolder = url

                // Notify app to open main window, then close onboarding
                NotificationCenter.default.post(name: .bttrflyDidPickFolder, object: nil)
                self.finishAndClose()
            } else {            // 🚫 User cancelled
                // Bring the onboarding window back
                onboardingWin.makeKeyAndOrderFront(nil)
                self.fade(onboardingWin, visible: true)
            }
        }
    }

    private func finishAndClose() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: hasOnboardedKey)            // mark onboarding done
        defaults.set(currentVersion, forKey: lastSeenKey)      // remember current version
        fade(window, visible: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.parent?.removeChildWindow(self.window!)
            self.window?.close()
            self.window = nil
        }
    }

    private func fade(_ win: NSWindow?, visible: Bool) {
        guard let win else { return }
        win.alphaValue = visible ? 0 : 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().alphaValue = visible ? 1 : 0
        }
    }
}
