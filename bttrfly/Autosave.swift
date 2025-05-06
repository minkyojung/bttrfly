import Combine
import Foundation

/// 텍스트 변경을 감지해 일정 시간 뒤 자동 저장.
final class AutosaveService {
    private var cancellable: AnyCancellable?
    private weak var model: MarkdownModel?

    init(model: MarkdownModel, interval: TimeInterval = 3) {
        self.model = model
        cancellable = model.$text
            .dropFirst()                      // 초기 로드 무시
            .removeDuplicates()               // 동일 내용 반복 저장 방지
            .debounce(for: .seconds(interval),
                      scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveIfPossible()
            }
    }

    private func saveIfPossible() {
        guard let model else { return }
        do { try model.save() }          // url==nil이면 autoGenerateURL() 호출
        catch { print("❌ Autosave failed:", error) }
    }
}
