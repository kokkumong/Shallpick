import Foundation
import Supabase

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

/// supabase/migrations 의 public.question_votes, public.question_pins
enum QuestionResponseRepository {
    static let maxPinLength = 300

    private struct NewVote: Encodable {
        let message_id: UUID
        let photo_id: UUID
        let folder_id: UUID
        let vote: QuestionVote
    }

    private struct NewPin: Encodable {
        let id: UUID
        let message_id: UUID
        let photo_id: UUID
        let folder_id: UUID
        let x: Double
        let y: Double
        let body: String
    }

    private static var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }
            return client
        }
    }

    /// userID 를 주면 그 사람 것만
    static func fetchVotes(messageID: UUID, userID: UUID? = nil) async throws -> [QuestionVoteRecord] {
        if DemoStore.shared.isActive { return DemoStore.shared.questionVotes.filter { $0.messageID == messageID && (userID == nil || $0.userID == userID) } }
        var query = try client
            .from("question_votes")
            .select("message_id, photo_id, user_id, vote, created_at")
            .eq("message_id", value: messageID)
        if let userID { query = query.eq("user_id", value: userID) }
        return try await query
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// 오래된 것 → 최신 순. userID 를 주면 그 사람 것만
    static func fetchPins(messageID: UUID, userID: UUID? = nil) async throws -> [QuestionPin] {
        if DemoStore.shared.isActive { return DemoStore.shared.questionPins.filter { $0.messageID == messageID && (userID == nil || $0.userID == userID) } }
        var query = try client
            .from("question_pins")
            .select()
            .eq("message_id", value: messageID)
        if let userID { query = query.eq("user_id", value: userID) }
        return try await query
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// 이미 남겼으면 바꿈
    static func setVote(_ vote: QuestionVote, messageID: UUID, folderID: UUID, photoID: UUID) async throws {
        if DemoStore.shared.isActive {
            if DemoStore.shared.failNextVote {
                DemoStore.shared.failNextVote = false
                throw URLError(.notConnectedToInternet)
            }
            DemoStore.shared.setVote(vote, messageID: messageID, photoID: photoID); return }
        try await client
            .from("question_votes")
            .upsert(
                NewVote(message_id: messageID, photo_id: photoID, folder_id: folderID, vote: vote),
                onConflict: "message_id,photo_id,user_id",
                returning: .minimal
            )
            .execute()
    }

    static func addPin(
        id: UUID,
        messageID: UUID,
        folderID: UUID,
        photoID: UUID,
        x: Double,
        y: Double,
        body: String
    ) async throws -> QuestionPin {
        if DemoStore.shared.isActive {
            let pin = QuestionPin(id: id, messageID: messageID, photoID: photoID, userID: DemoStore.shared.userID,
                x: min(max(x, 0), 1), y: min(max(y, 0), 1), body: String(body.prefix(maxPinLength)), createdAt: .now)
            DemoStore.shared.questionPins.append(pin)
            return pin
        }
        return try await client
            .from("question_pins")
            .insert(NewPin(id: id, message_id: messageID, photo_id: photoID, folder_id: folderID, x: x, y: y, body: body))
            .select()
            .single()
            .execute()
            .value
    }

    static func deletePin(id: UUID) async throws {
        if DemoStore.shared.isActive { DemoStore.shared.questionPins.removeAll { $0.id == id && $0.userID == DemoStore.shared.userID }; return }
        try await client
            .from("question_pins")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
