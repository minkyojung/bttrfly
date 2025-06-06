//
//  WhatsNewController.swift
//  bttrfly
//
//  Temporary placeholder that just shows an alert.
//  Replace with a richer SwiftUI sheet later.
//

import AppKit

final class WhatsNewController {

    /// Presents a simple modal alert describing what's new.
    func present() {
        let version = Bundle.main.shortVersion
        
        let alert = NSAlert()
        alert.messageText = "What’s New in Bttrfly \(version)"
        alert.informativeText =
        """
        • 초기 온보딩 플로우 개선
        • 업데이트 알림 버튼 추가
        • 전반적인 버그 수정 및 최적화
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        // 현재 버전을 본 것으로 기록
        UserDefaults.standard.set(version, forKey: "bttrflyLastSeenVersion")
    }
}
