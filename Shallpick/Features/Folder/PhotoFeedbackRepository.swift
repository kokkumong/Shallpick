import Foundation
import Supabase

/// 사진에 남긴 이모지 반응 한 개 (한 사람이 이모지마다 하나)
nonisolated struct PhotoReaction: Codable, Sendable, Hashable {
    let photoID: UUID
    let userID: UUID
    let emoji: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case userID = "user_id"
        case emoji
        case createdAt = "created_at"
    }
}

/// 사진에 남긴 생각(댓글)
nonisolated struct PhotoComment: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let photoID: UUID
    let userID: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case photoID = "photo_id"
        case userID = "user_id"
        case body
        case createdAt = "created_at"
    }
}

/// supabase/migrations 의 public.photo_reactions, public.photo_comments
enum PhotoFeedbackRepository {
    static let maxCommentLength = 1000
    /// 사진을 두 번 누르면 켜지고 꺼지는 반응
    static let heart = "❤️"
    /// 이모지 추가 버튼에서 고를 수 있는 반응
    static let palette = ["❤️", "😆", "🤨", "😢", "👍", "🔥", "😍", "😮"]

    private struct NewReaction: Encodable {
        let photo_id: UUID
        let emoji: String
    }

    private struct NewComment: Encodable {
        let id: UUID
        let photo_id: UUID
        let body: String
    }

    private static var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }
            return client
        }
    }

    /// 반응 (먼저 남긴 순)
    static func fetchReactions(photoID: UUID) async throws -> [PhotoReaction] {
        if DemoStore.shared.isActive { return DemoStore.shared.photoReactions.filter { $0.photoID == photoID } }
        return try await client
            .from("photo_reactions")
            .select()
            .eq("photo_id", value: photoID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func likedPhotoIDs(in photos: [PhotoItem]) async throws -> Set<UUID> {
        if DemoStore.shared.isActive { return Set(DemoStore.shared.photoReactions.filter { $0.userID == DemoStore.shared.userID && $0.emoji == heart }.map(\.photoID)) }
        guard let me = PhotoRepository.currentUserID else { throw FolderRepository.FolderError.notConfigured }
        var result: Set<UUID> = []
        // One reaction per user/photo/emoji; chunks stay below the API row cap.
        for start in stride(from: 0, to: photos.count, by: 100) {
            let ids = photos[start..<min(start + 100, photos.count)].map(\.id)
            let rows: [PhotoReaction] = try await client.from("photo_reactions").select()
                .eq("user_id", value: me).eq("emoji", value: heart).in("photo_id", values: ids).execute().value
            result.formUnion(rows.map(\.photoID))
        }
        return result
    }

    /// 댓글 (오래된 것 → 최신 순)
    static func fetchComments(photoID: UUID) async throws -> [PhotoComment] {
        if DemoStore.shared.isActive { return DemoStore.shared.photoComments.filter { $0.photoID == photoID } }
        return try await client
            .from("photo_comments")
            .select()
            .eq("photo_id", value: photoID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// 이미 같은 반응이 있으면 (빠르게 두 번 누른 경우 등) 그대로 둠
    static func addReaction(photoID: UUID, emoji: String) async throws {
        if DemoStore.shared.isActive {
            let demo = DemoStore.shared
            if !demo.photoReactions.contains(where: { $0.photoID == photoID && $0.userID == demo.userID && $0.emoji == emoji }) {
                demo.photoReactions.append(PhotoReaction(photoID: photoID, userID: demo.userID, emoji: emoji, createdAt: .now))
            }
            return
        }
        try await client
            .from("photo_reactions")
            .upsert(NewReaction(photo_id: photoID, emoji: emoji), onConflict: "photo_id,user_id,emoji", returning: .minimal, ignoreDuplicates: true)
            .execute()
    }

    static func removeReaction(photoID: UUID, emoji: String) async throws {
        if DemoStore.shared.isActive { DemoStore.shared.photoReactions.removeAll { $0.photoID == photoID && $0.userID == DemoStore.shared.userID && $0.emoji == emoji }; return }
        guard let me = PhotoRepository.currentUserID else { return }
        try await client
            .from("photo_reactions")
            .delete()
            .eq("photo_id", value: photoID)
            .eq("user_id", value: me)
            .eq("emoji", value: emoji)
            .execute()
    }

    static func addComment(id: UUID, photoID: UUID, body: String) async throws -> PhotoComment {
        if DemoStore.shared.isActive {
            let comment = PhotoComment(id: id, photoID: photoID, userID: DemoStore.shared.userID, body: String(body.prefix(maxCommentLength)), createdAt: .now)
            DemoStore.shared.photoComments.append(comment)
            return comment
        }
        return try await client
            .from("photo_comments")
            .insert(NewComment(id: id, photo_id: photoID, body: body))
            .select()
            .single()
            .execute()
            .value
    }

    static func deleteComment(id: UUID) async throws {
        if DemoStore.shared.isActive { DemoStore.shared.photoComments.removeAll { $0.id == id && $0.userID == DemoStore.shared.userID }; return }
        try await client
            .from("photo_comments")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

/// "방금 전" / "n분 전" / "n시간 전" / "n일 전"
enum RelativeTimeText {
    static func format(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "방금 전"
        case ..<3600: return "\(seconds / 60)분 전"
        case ..<86400: return "\(seconds / 3600)시간 전"
        default: return "\(seconds / 86400)일 전"
        }
    }
}
