import Foundation

/// 사진 질문의 사진 하나에 남긴 좋아/싫어
nonisolated enum QuestionVote: String, Codable, Sendable {
    case like
    case dislike

    var label: String {
        switch self {
        case .like: "좋아"
        case .dislike: "싫어"
        }
    }
}

/// public.question_votes 한 줄
nonisolated struct QuestionVoteRecord: Codable, Sendable, Hashable {
    let messageID: UUID
    let photoID: UUID
    let userID: UUID
    let vote: QuestionVote
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case photoID = "photo_id"
        case userID = "user_id"
        case vote
        case createdAt = "created_at"
    }
}

/// 사진 위 한 점에 남긴 댓글 (x, y 는 사진 안 비율 0~1)
nonisolated struct QuestionPin: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let messageID: UUID
    let photoID: UUID
    let userID: UUID
    let x: Double
    let y: Double
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case messageID = "message_id"
        case photoID = "photo_id"
        case userID = "user_id"
        case x, y, body
        case createdAt = "created_at"
    }
}

