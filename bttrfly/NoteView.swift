// NoteView.swift
import SwiftUI
import AppKit

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .withinWindow
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
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.7) // ← 두께 2 pt
                )
                .ignoresSafeArea()           // 블러도 타이틀바까지
                .overlay(                       // dark overlay *above* the blur
                    (cs == .dark
                        ? Color.black.opacity(0.15)      // 다크: 15 % 암막
                        : Color.white.opacity(0.15))     // 라이트: 8 % 화이트 글레이즈로 더 하얗게
                        .ignoresSafeArea()
                )
            
            // ③ 실제 에디터
            WebView(model: model)
                .padding(.horizontal, 12)
                .onAppear {
                                    print("🪵 NoteView sees →", model.debugID)
                                }
        }
        .frame(minWidth: 330, minHeight: 480)
    }
}
