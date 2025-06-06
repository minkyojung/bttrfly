//
//  bttrflyApp.swift
//  bttrfly
//
//  Created by William Jung on 4/27/25.
//



import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts
import QuartzCore
import Sparkle
import Mixpanel
import WebKit          // for WKWebView reference

enum LaunchFlow { case onboarding, whatsNew, main }


enum AppTheme: Int, CaseIterable, Identifiable {
    case system, light, dark
    var id: Int { rawValue }
    /// Returns the appropriate SwiftUI `ColorScheme` or `nil` (follow system)
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// A container that updates the color scheme live whenever the user changes the theme
struct ThemedRootView: View {
    @AppStorage("appTheme") private var appThemeRaw: Int = AppTheme.system.rawValue
    let model: MarkdownModel
    var body: some View {
        NoteView(model: model)
            .preferredColorScheme(
                AppTheme(rawValue: appThemeRaw)?.colorScheme
            )
    }
}

@main
struct MyFloatingMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // A hidden settings scene is enough to satisfy SwiftUI’s requirement
        // for at least one `Scene`, while avoiding an empty window opening.
        Settings {
            CombinedPrefs()
                .environmentObject(appDelegate.model)
                .frame(width: 600, height: 420)
        }
        .commands {
            MainCommands()
            
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    print("🔔 메뉴 클릭")          // 디버그용 로그
                    appDelegate.updater?.checkForUpdates()
                }
            }
        }
        
    }
}

struct GeneralPrefs: View {
    @AppStorage("showDefaultFolder") private var showDefaultFolder = true
    @AppStorage("appTheme") private var appThemeRaw: Int = AppTheme.system.rawValue
    var body: some View {
        Form {
            Toggle("Show Bttrfly folder in Favorites", isOn: $showDefaultFolder)

            Section("Appearance") {
                Picker("Theme", selection: $appThemeRaw) {
                    Text("Automatic").tag(AppTheme.system.rawValue)
                    Text("Light").tag(AppTheme.light.rawValue)
                    Text("Dark").tag(AppTheme.dark.rawValue)
                }
                .pickerStyle(.radioGroup)
            }
        }
        .padding(20)
    }
}

// MARK: - Combined settings (single pane)
struct CombinedPrefs: View {
    @EnvironmentObject var model: MarkdownModel
    // existing stored prefs
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue
    @AppStorage("showDefaultFolder") private var showDefaultFolder = true
    @AppStorage("statsNoteCount") private var statsNoteCount: Int = 0
    @AppStorage("statsCharCount") private var statsCharCount: Int = 0
    @AppStorage("statsFocusSeconds") private var statsFocusSeconds: Int = 0
    @AppStorage("statsTodoDone")     private var statsTodoDone: Int = 0
    @AppStorage("statsSessionStart") private var statsSessionStart: Double = 0   // UNIX timestamp; 0 = no active session
    @State private var refreshTick = Date()     // forces view update every minute

    // static developer info
    private let devName  = "William Jung"
    private let devEmail = "williamjung@bttrfly.me"
    private let blogURL  = URL(string: "https://bttrflynote.substack.com/")!

    var body: some View {
        Form {
            // ── Application ─────────────────────────
            Section("App") {
                HStack {
                    Label("Theme", systemImage: "paintbrush")
                    Spacer()
                    Picker("", selection: $appThemeRaw) {
                        Text("Automatic").tag(AppTheme.system.rawValue)
                        Text("Light").tag(AppTheme.light.rawValue)
                        Text("Dark").tag(AppTheme.dark.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Toggle(isOn: $showDefaultFolder) {
                    Label("Show Bttrfly folder in Favorites", systemImage: "folder")
                }

                HStack {
                    Label("Note Window Shortcut", systemImage: "keyboard")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .showNote)
                }
            }

            // ── Storage ─────────────────────────
            Section("Storage") {
                HStack {
                    Label("Save Folder", systemImage: "folder.fill")
                    Spacer()
                    Text(model.saveFolder?.lastPathComponent ?? "Not set")
                        .foregroundColor(.secondary)
                    Button("Change…") {
                        model.endSession()                       // finish current focus session
                        model.chooseSaveFolder { _ in            // async picker
                            // Start a fresh scratch note in the NEW folder
                            DispatchQueue.main.async {
                                model.createNewFile()
                            }
                        }
                    }
                }

                if let folder = model.saveFolder {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    .buttonStyle(.link)
                }
            }

            // ── Stats ─────────────────────────
            Section("Stats") {
                HStack {
                    Label("Notes", systemImage: "doc.plaintext")
                    Spacer()
                    Text("\(statsNoteCount)")
                }
                HStack {
                    Label("Characters", systemImage: "character.cursor.ibeam")
                    Spacer()
                    Text(statsCharCount.formatted())
                }
                HStack {
                    Label("Focus Time", systemImage: "timer")
                    Spacer()
                    Text(timeString(from: totalFocusSeconds))
                }
                HStack {
                    Label("Todos Done", systemImage: "checkmark.square")
                    Spacer()
                    Text("\(statsTodoDone)")
                }
            }

            // ── Developer ───────────────────────────
            Section("Developer") {
                HStack {
                    Label("Name", systemImage: "person")
                    Spacer()
                    Text(devName)
                }

                HStack {
                    Label("Email", systemImage: "envelope")
                    Spacer()
                    Button(devEmail) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(devEmail, forType: .string)
                    }
                    .buttonStyle(.link)
                    .help("Click to copy")
                }

                HStack {
                    Label("Blog", systemImage: "link")
                    Spacer()
                    Link(blogURL.absoluteString, destination: blogURL)
                        .lineLimit(1)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .id(refreshTick)              // force redraw when the tick changes
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshTick = Date()
        }
    }
    // Convert seconds to "Hh Mm" string
    private func timeString(from seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        return "\(hrs)h \(mins)m"
    }
    // Total focus = stored seconds + current running session (if any)
    private var totalFocusSeconds: Int {
        let running = statsSessionStart > 0 ? Int(Date().timeIntervalSince1970 - statsSessionStart) : 0
        return statsFocusSeconds + running
    }
}

// MARK: - Developer profile preferences
// MARK: - Developer profile (read-only)
struct ProfilePrefs: View {
    private let name  = "William Jung"
    private let email = "williamjung0130@gmail.com"
    private let blog  = URL(string: "https://bttrflynote.substack.com/")!

    var body: some View {
        Form {
            Section("Developer") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(name)
                }

                HStack {
                    Text("Email")
                    Spacer()
                    Button(email) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(email, forType: .string)
                    }
                    .buttonStyle(.link)
                    .help("Click to copy")
                }
            }

            Section("Blog") {
                Link(blog.absoluteString, destination: blog)
            }
        }
        .padding(20)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var panel: FloatingPanelController?
    private var welcomePanel: NSWindowController?
    private let hasSeenWelcomeKey = "bttrflyHasSeenWelcome"
    private var onboarding: OnboardingController?
    let model = MarkdownModel.shared
    private var autosave: AutosaveService?
    /// Opacity for the welcome‑panel dim layer
    private let welcomeDimAlpha: CGFloat = 0.45
    /// Sparkle updater controller
    private var updaterController: SPUStandardUpdaterController?
    /// Expose Sparkle’s underlying updater
    var updater: SPUUpdater? { updaterController?.updater }
    /// WebView reference for Swift → JS callbacks
    weak var webView: WKWebView?
    /// Flag to ensure the bundled quick guide is only inserted once
    @AppStorage("didInsertQuickGuide") private var didInsertQuickGuide = false

    /// Decide which UI flow to start on launch
    private func decideLaunchFlow() -> LaunchFlow {
        let d = UserDefaults.standard
        let version = Bundle.main.shortVersion
        
        // First‑time run OR folder not chosen → onboarding
        if !d.bool(forKey: "bttrflyHasOnboarded") ||
           d.url(forKey: "bttrflySaveFolder") == nil {
            return .onboarding
        }
        // Seen onboarding but new marketing version → what's‑new
        if d.string(forKey: "bttrflyLastSeenVersion") != version {
            return .whatsNew
        }
        // Otherwise go straight to main app UI
        return .main
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // 🔎 Print SUFeedURL to verify which feed this build is using
        print("👉 SUFeedURL =", Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "nil")
        print("👉 ArbitraryLoads =", Bundle.main.object(forInfoDictionaryKey: "NSAllowsArbitraryLoads") ?? "nil")
        #if DEBUG
        // Always restart onboarding in DEBUG builds
        UserDefaults.standard.removeObject(forKey: "bttrflyHasOnboarded")
        UserDefaults.standard.removeObject(forKey: "bttrflySaveFolder")
        if CommandLine.arguments.contains("-resetGuide") {
            UserDefaults.standard.removeObject(forKey: "didInsertQuickGuide")
        }
        #endif
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didPickFolder),
                                               name: .bttrflyDidPickFolder,
                                               object: nil)

        // 🚀 Mixpanel 초기화 (DEV/PROD 자동 분기)
        let token = Bundle.main.infoDictionary?["MixpanelToken"] as? String ?? ""
        print("🚩 Mixpanel token:", token)
        Mixpanel.initialize(token: token)
        Mixpanel.mainInstance().loggingEnabled = true
        Mixpanel.mainInstance().identify(distinctId: MarkdownModel.shared.debugID.uuidString)
        Mixpanel.mainInstance().track(event: "app_launch")

        // Restore previously‑chosen save folder, preferring the security‑scoped bookmark
        if let restored = model.loadSavedFolderURL() ??
                          UserDefaults.standard.url(forKey: "bttrflySaveFolder") {
            model.saveFolder = restored
        }

        // Launch‑flow switch
        switch decideLaunchFlow() {
        case .onboarding:
            onboarding = OnboardingController(model: model)
            onboarding?.presentIfNeeded()
            
        case .whatsNew:
            // Temporary alert‑style What's‑New until a full controller exists
            WhatsNewController().present()
            
        case .main:
            createMainPanel()
        }

        // Start Sparkle automatic updater (checks on launch)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updater?.checkForUpdatesInBackground()      // force first check on launch
        if let upd = updaterController?.updater {
            print("🟢 SPUUpdater created =", upd)
            print("🟢 canCheckForUpdates =", upd.canCheckForUpdates)
            print("🟢 automaticallyChecksForUpdates =", upd.automaticallyChecksForUpdates)
        } else {
            print("🔴 updaterController is nil!")
        }
        // Register global shortcut
        KeyboardShortcuts.onKeyUp(for: .showNote) { [weak self] in
            self?.toggleNote()
        }
    }

    @objc func openDocument(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            // Create a security‑scoped bookmark
            guard let bm = try? url.bookmarkData(options: .withSecurityScope,
                                                 includingResourceValuesForKeys: nil,
                                                 relativeTo: nil) else { return }
            // Save to recent list
            RecentFileManager.shared.add(url: url, bookmark: bm)
            // Load into model (model handles scope)
            try? model.load(fileURL: url, bookmark: bm)
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        do {
            try model.save()
        } catch {
            print("❌ Failed to save markdown file:", error)
        }
    }
    // Toggle the floating note window via global shortcut
    private func toggleNote() {
        guard let panel = panel else { return }
        if panel.window?.isVisible == true {
            panel.close()
        } else {
            panel.showWindow(nil)
            panel.window?.makeKey()        // bring to front
        }
    }

    @objc private func didPickFolder() {          // notification receiver
        createMainPanel()
    }

    private func createMainPanel() {
        guard panel == nil else { return }        // already created once
        let rootView = ThemedRootView(model: model)

        panel = FloatingPanelController(root: rootView, model: model)
        panel?.showWindow(nil)
        SearchPanelController.shared.configure(model: model)
        autosave = AutosaveService(model: model)
        model.startSession()     // begin focus timer for initial window

        // Insert bundled quick guide on first run
        if let folder = model.saveFolder {
            insertQuickGuideIfNeeded(at: folder)
        }
    }

    // MARK: - Quick guide insertion
    /// Copies the bundled quick‑guide into the chosen folder on first run and opens it.
    private func insertQuickGuideIfNeeded(at folder: URL) {
        let destURL = folder.appendingPathComponent("Quick_Guide_for_Bttrfly.md")

        // ① Always remove the old guide so edits in the app bundle propagate immediately
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }

        // ② Copy the latest guide from the app bundle
        if let srcURL = Bundle.main.url(forResource: "Guide", withExtension: "md") {
            try? FileManager.default.copyItem(at: srcURL, to: destURL)
        }

        // ③ Load the (fresh) guide into the editor
        try? model.load(fileURL: destURL)

        // ④ Record that we've at least inserted once (optional—but harmless)
        didInsertQuickGuide = true
    }

    // MARK: - First‑run welcome
    private func presentWelcomeIfNeeded() {
        // Skip if user dismissed it before
        guard !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey) else { return }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        let wrapper = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 14

        let blur = NSVisualEffectView(frame: wrapper.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .underWindowBackground                     // configurable
        blur.state = .active
        wrapper.addSubview(blur)

        let dim = NSView(frame: wrapper.bounds)
        dim.autoresizingMask = [.width, .height]
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(welcomeDimAlpha).cgColor
        wrapper.addSubview(dim)

        let host = NSHostingController(rootView: WelcomeView { [weak self] in
            guard let self = self else { return }

            // Close the welcome panel immediately so the Finder picker isn’t hidden
            self.welcomePanel?.close()
            self.welcomePanel = nil

            // Show folder chooser (hop onto Main actor)
            Task { @MainActor in
                self.model.chooseSaveFolder { folder in
                    if folder != nil {
                        UserDefaults.standard.set(true, forKey: self.hasSeenWelcomeKey)
                    }
                }
            }
        })
        blur.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: blur.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: blur.trailingAnchor)
        ])

        panel.contentView = wrapper

        if let screen = NSScreen.main {
            panel.center()
        }

        welcomePanel = NSWindowController(window: panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }
    // MARK: - Sparkle delegate
    func updater(_ updater: SPUUpdater,
                 didFindValidUpdate item: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) {
        print("🟢 delegate didFindValidUpdate 👀:", item.versionString)
        // Persist flag so banner survives app restarts
        UserDefaults.standard.set(item.displayVersionString,
                                  forKey: "bttrflyUpdateReady")

        // Notify SwiftUI / WebView to show update banner
        NotificationCenter.default.post(name: .bttrflyDidDetectUpdate,
                                        object: item)
        // Also notify the HTML bottom‑bar
        if let wv = webView {
            let js = "window.bttrflyUpdateReady('\\(item.displayVersionString)')"
            wv.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// Clear flag after successful install‑and‑relaunch
    func updaterDidFinishUpdateCycle(_ updater: SPUUpdater) {
        print("🟢 delegate didFinishUpdateCycle")
        UserDefaults.standard.removeObject(forKey: "bttrflyUpdateReady")
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let bttrflyDidDetectUpdate = Notification.Name("bttrflyDidDetectUpdate")
}

// MARK: - Raycast‑style welcome view
struct WelcomeView: View {
    var pickAction: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text("Choose a Folder")
                .font(.title2).bold()

            Text("bttrfly needs a location to save your Markdown notes. You can change this later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            Button("Select Folder…", action: pickAction)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
        }
        .padding(32)
        .frame(width: 360, height: 200)
    }
}
