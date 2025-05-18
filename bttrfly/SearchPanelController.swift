import Foundation
import AppKit
import SwiftUI
import Combine

// MARK: - Global notifications
extension Notification.Name {
    /// index (Int, zero‑based) of the pinned folder to open
    static let OpenPinned = Notification.Name("OpenPinned")
}

/// Custom NSPanel that *can* become key/main, so underlying editor stops receiving keystrokes.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// ⌘1–⌘9 → post `.OpenPinned` with zero‑based index
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.characters,
              let n = Int(chars),
              (1...9).contains(n) else {
            return super.performKeyEquivalent(with: event)
        }
        NotificationCenter.default.post(name: .OpenPinned, object: n - 1)
        return true    // consume the event
    }
}

/// Floating panel that hosts QuickOpenView and doesn’t steal focus.
final class SearchPanelController: NSWindowController {

    // MARK: Singleton
    static let shared = SearchPanelController()

    /// Adjustable panel border thickness
    private let borderWidth: CGFloat = 0.0  // no border
    private var model: MarkdownModel!       // injected from the editor
    private var blurView: NSVisualEffectView!   // keep reference for later
    private var hosting: NSHostingController<QuickOpenView>?   // lazy‑created
    private var cancellables = Set<AnyCancellable>()

    // MARK: Private
    private var isShown = false
    private var eventMonitors: [Any] = []   // ESC / outside‑click monitors

    // MARK: Init
    private init() {
        // Create panel
        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true


        // ---- Wrapper with shadow ---------------------------------------
        let wrapper = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        wrapper.wantsLayer = true
        wrapper.autoresizingMask = [.width, .height]

        wrapper.layer?.cornerRadius = 14
        // wrapper.layer?.borderWidth = borderWidth      // borderWidth is 0.3 at top
        let dynamicBorder = NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                // Dark‑mode: very subtle light border
                return NSColor.white.withAlphaComponent(0.08)
            } else {
                // Light‑mode: soft dark border
                return NSColor.black.withAlphaComponent(0.15)
            }
        })
        // wrapper.layer?.borderColor = dynamicBorder.cgColor
        wrapper.layer?.masksToBounds = false

        panel.isMovableByWindowBackground = false   // disable dragging
        panel.isMovable = false                     // no titlebar dragging either
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // ---- Blur layer -------------------------------------------------
        let blurView = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        blurView.autoresizingMask = [.width, .height]
        blurView.material = .underWindowBackground      // match note‑panel material
        blurView.blendingMode = .withinWindow           // keep tint visible
        blurView.state = .active
        // Glassmorphism: translucent blur background in all modes
        blurView.material = .underWindowBackground
        blurView.blendingMode = .withinWindow
        blurView.state = .active
        blurView.wantsLayer = true

        wrapper.addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
        ])
        // store reference for later
        self.blurView = blurView

        // ---- Shadow overlay (frontmost, transparent) -------------------
        let shadowOverlay = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        shadowOverlay.wantsLayer = true
        shadowOverlay.autoresizingMask = [.width, .height]

        shadowOverlay.layer?.cornerRadius = 14
        shadowOverlay.layer?.masksToBounds = false
        shadowOverlay.layer?.backgroundColor = NSColor.clear.cgColor
        shadowOverlay.layer?.shadowColor = NSColor.black.cgColor
        shadowOverlay.layer?.shadowOpacity = 0.45
        shadowOverlay.layer?.shadowRadius = 18
        shadowOverlay.layer?.shadowOffset = .zero

        wrapper.addSubview(shadowOverlay)

        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.001)
        panel.hasShadow = true   // enable window drop shadow for better separation

        panel.contentView = wrapper
        super.init(window: panel)
        window?.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - External configuration
    /// Call once from the main editor to share its MarkdownModel.
    func configure(model: MarkdownModel) {
        // If already configured, just swap the rootView
        if let existing = hosting {
            self.model = model
            // Close the panel whenever a new file is loaded in the editor
            cancellables.removeAll()
            model.$currentFileName
                .dropFirst()                    // ignore initial value
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.hide()
                    self?.isShown = false
                }
                .store(in: &cancellables)
            existing.rootView = QuickOpenView(model: model)
            return
        }

        // First‑time configuration
        self.model = model
        // Close the panel whenever a new file is loaded in the editor
        cancellables.removeAll()
        model.$currentFileName
            .dropFirst()                    // ignore initial value
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.hide()
                self?.isShown = false
            }
            .store(in: &cancellables)
        let host = NSHostingController(rootView: QuickOpenView(model: model))
        self.hosting = host

        blurView.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: blurView.topAnchor, constant: 12),
            host.view.bottomAnchor.constraint(equalTo: blurView.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: blurView.trailingAnchor)
        ])
    }

    // MARK: - Animations
    private func show(relativeTo parent: NSWindow?) {
        guard let panel = window else { return }

        // Position first
        if let parent = parent {
            let x = parent.frame.midX - panel.frame.width / 2
            let y = parent.frame.maxY - panel.frame.height - 40
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            parent.addChildWindow(panel, ordered: .above)
            panel.hasShadow = true            // force shadow even for child window
        }

        // Start transparent
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)


        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }

        // ── Install event monitors ─────────────────────────────────────
        // Local Esc‑key monitor
        let esc = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 {          // 53 == Esc
                self?.hide()
                self?.isShown = false
                return nil                 // consume event
            }
            return ev
        }
    
        // Global mouse click monitor
        let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.window else { return }
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                self.hide()
                self.isShown = false
            }
        }
    
        eventMonitors = [esc as Any, click as Any]
    }

    private func hide() {
        guard let panel = window else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }) { [self] in
            for monitor in eventMonitors {
                NSEvent.removeMonitor(monitor)
            }
            eventMonitors.removeAll()

            panel.orderOut(nil)
        }
    }

    // MARK: Public
    /// Toggle visibility, positioning above a parent window if provided.
    func toggle(relativeTo parent: NSWindow?) {
        if isShown {
            isShown = false
            hide()
        } else {
            isShown = true
            show(relativeTo: parent)
        }
    }
}

//
//#if DEBUG
//import SwiftUI
//
//struct SearchPanelController_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            QuickOpenView()                       // 기본
//            QuickOpenView()                       // 다크모드
//                .preferredColorScheme(.dark)
//        }
//        .frame(width: 300, height: 330)
//    }
//}
//#endif
//
