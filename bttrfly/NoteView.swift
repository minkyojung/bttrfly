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
    @Environment(\.colorScheme) var cs
    @ObservedObject var model: MarkdownModel
    
    var body: some View {
        ZStack {
            // ① VisualEffectBlur + 테두리
            VisualEffectBlur(material: .underWindowBackground)
                .background(          // ② 바로 ‘뒤’에 암막을 깐다
                    Color.black.opacity(cs == .dark ? 0.5 : 0.18)
                        .ignoresSafeArea()   // 타이틀바까지 확장
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .ignoresSafeArea()           // 블러도 타이틀바까지
            
            // ③ 실제 에디터
            WebView(model: model)
                .padding(.horizontal, 12)
        }
        .frame(minWidth: 330, minHeight: 480)
    }
}
