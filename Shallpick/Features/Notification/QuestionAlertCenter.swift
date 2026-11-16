import Foundation
import Observation

/// 앱 안에서 띄우는 질문 알림 한 건
struct QuestionAlert: Identifiable, Equatable {
    /// 알림을 만든 메시지 id (같은 메시지로 두 번 뜨지 않게)
    let id: UUID
    let folder: Folder
    let askerNickname: String
    let question: String
    /// 폴더 그림에 꽂을 사진 (최대 3장, 없으면 빈 카드)
    var photoURLs: [URL] = []

    /// "현서로부터 질문이 왔어요" / "지원으로부터 질문이 왔어요"
    var headline: String {
        "\(askerNickname)\(askerNickname.fromParticle) 질문이 왔어요"
    }
}

/// 질문 알림 대기열. 한 번에 하나씩 화면 가운데에 띄웁니다.
@Observable
final class QuestionAlertCenter {
    private(set) var queue: [QuestionAlert] = []

    var current: QuestionAlert? { queue.first }

    func present(_ alert: QuestionAlert) {
        guard !queue.contains(where: { $0.id == alert.id }) else { return }
        queue.append(alert)
    }

    /// "나중에!" / "바로 응답하기" 를 누르면 지금 알림을 닫고 다음 것을 보여줌
    func dismissCurrent() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
    }
}

extension String {
    /// 받침이 있으면 "으로부터", 없거나 ㄹ 받침이면 "로부터"
    var fromParticle: String {
        guard let last = unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(last) else { return "로부터" }
        let jongseong = (last - 0xAC00) % 28
        return jongseong == 0 || jongseong == 8 ? "로부터" : "으로부터"
    }
}
