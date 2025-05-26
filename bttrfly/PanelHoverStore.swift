import Combine

/// 패널 안 팝업 전역 Hover 상태
final class PanelHoverStore: ObservableObject {
    @Published var isHovered: Bool = false
}
