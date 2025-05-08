// NoteView.swift
import SwiftUI
import AppKit

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}

struct NoteView: View {
    @ObservedObject var model: MarkdownModel     // 이미 쓰고 있는 모델

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .ignoresSafeArea()                    // let blur extend into titlebar
            WebView(model: model)
                .padding(.horizontal, 16)        // reduce left‑right margin
        }
        .frame(minWidth: 350, minHeight: 480)    // 패널 기본 크기
    }
}
