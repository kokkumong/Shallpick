import Foundation
import Observation

/// 계정별로 이 기기에 저장합니다. 읽지 않은 글의 수와 알림 표시 여부는 별개입니다.
@Observable
final class NotificationPreferences {
    enum Kind: String, CaseIterable, Identifiable {
        case photos, comments, reactions, messages, requests
        var id: String { rawValue }
        var title: String {
            switch self {
            case .photos: "사진 업로드"
            case .comments: "댓글"
            case .reactions: "공감"
            case .messages: "메시지"
            case .requests: "요청"
            }
        }
    }

    private let key: String
    private var values: [String: Bool]

    init(userID: UUID) {
        key = "notifications.preferences.\(userID)"
        values = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:]
    }

    func isEnabled(_ kind: Kind) -> Bool { values[kind.rawValue] ?? true }

    func set(_ enabled: Bool, for kind: Kind) {
        values[kind.rawValue] = enabled
        UserDefaults.standard.set(values, forKey: key)
    }
}
