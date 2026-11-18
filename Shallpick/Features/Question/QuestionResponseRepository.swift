import Foundation
import Supabase

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
        try await fetchVotes(messageIDs: [messageID], userID: userID)
    }

    static func fetchVotes(messageIDs: [UUID], userID: UUID? = nil) async throws -> [QuestionVoteRecord] {
        guard !messageIDs.isEmpty else { return [] }
        var query = try client
            .from("question_votes")
            .select("message_id, photo_id, user_id, vote, created_at")
            .in("message_id", values: messageIDs)
        if let userID { query = query.eq("user_id", value: userID) }
        var result: [QuestionVoteRecord] = []
        var offset = 0
        while true {
            let page: [QuestionVoteRecord] = try await query
                .order("message_id", ascending: true).order("photo_id", ascending: true).order("user_id", ascending: true)
                .range(from: offset, to: offset + 499).execute().value
            result += page
            if page.count < 500 { return result }
            offset += page.count
        }
    }

    /// 오래된 것 → 최신 순. userID 를 주면 그 사람 것만
    static func fetchPins(messageID: UUID, userID: UUID? = nil) async throws -> [QuestionPin] {
        var query = try client
            .from("question_pins")
            .select()
            .eq("message_id", value: messageID)
        if let userID { query = query.eq("user_id", value: userID) }
        var result: [QuestionPin] = []
        var offset = 0
        while true {
            let page: [QuestionPin] = try await query.order("created_at", ascending: true)
                .order("id", ascending: true).range(from: offset, to: offset + 499).execute().value
            result += page
            if page.count < 500 { return result }
            offset += page.count
        }
    }

    /// 이미 남겼으면 바꿈
    static func setVote(_ vote: QuestionVote, messageID: UUID, folderID: UUID, photoID: UUID) async throws {
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
        if let existing = try await fetchPins(messageID: messageID).first(where: { $0.id == id }) { return existing }
        return try await client
            .from("question_pins")
            .insert(NewPin(id: id, message_id: messageID, photo_id: photoID, folder_id: folderID, x: x, y: y, body: body))
            .select()
            .single()
            .execute()
            .value
    }

    static func deletePin(id: UUID) async throws {
        try await client
            .from("question_pins")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
