//
//  bttrflyApp.swift
//  bttrfly
//
//  Created by William Jung on 4/27/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct MyFloatingMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { WindowGroup { EmptyView() } }
    
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanelController?
    let model = MarkdownModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanelController(root: WebView(model: model))
        panel?.showWindow(nil)
        // 메뉴는 메인 메뉴가 완전히 구성된 뒤에 삽입해야 안전하다
        DispatchQueue.main.async { [weak self] in
            self?.addMenuItems()
        }
    }

    @objc func openDocument(_ sender: Any?) {
        // 패널이 non‑activating일 때도 단축키·메뉴가 동작하도록 앱을 활성화
        NSApp.activate(ignoringOtherApps: true)
        print("💡 openDocument fired")
        let open = NSOpenPanel()
        open.allowedContentTypes = [UTType(importedAs: "net.daringfireball.markdown")]
        open.begin { [weak self] response in
            guard response == .OK, let url = open.url else { return }
            do {
                try self?.model.load(fileURL: url)
            } catch {
                print("Failed to load markdown file:", error)
            }
        }
    }

    private func addMenuItems() {
        // ① File / 파일 메뉴 찾기 (다국어 대응)
        guard let main = NSApp.mainMenu,
              let fileMenu = main.items.first(where: { ["File", "파일"].contains($0.title) })?.submenu
        else { print("❌ File menu not found"); return }

        // ② 이미 “Open…” 이 있는지 확인해 중복 방지
        if fileMenu.items.contains(where: { $0.action == #selector(openDocument(_:)) }) {
            print("ℹ️ Open… already present"); return
        }

        let openItem = NSMenuItem(title: "Open…",
                                  action: #selector(openDocument(_:)),
                                  keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self                     // 🔑 꼭 지정
        fileMenu.insertItem(openItem, at: 0)
        
        
        
        // 디버그 로그
        print("✅ Open… inserted. File menu items:", fileMenu.items.map(\.title))
    }
}
