import SwiftUI


struct GlassBackground: View {
    var radius: CGFloat = 16      // 모서리 둥글기

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)                 // ① 흐림 + 기본 색
            .overlay(                                 // ② 얇은 밝은 테두리
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25),      // ③ 아래쪽에 부드러운 그림자
                    radius: 10, y: 10)
    }
}
