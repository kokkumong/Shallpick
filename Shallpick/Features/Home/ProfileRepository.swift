import Foundation
import Supabase

nonisolated struct Profile: Decodable, Sendable {
    let id: UUID
    let nickname: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case avatarURL = "avatar_url"
    }
}

/// supabase/migrations 의 public.profiles 테이블
enum ProfileRepository {
    static func fetch(userID: UUID) async throws -> Profile? {
        if DemoStore.shared.isActive { return Profile(id: userID, nickname: "시연 사용자", avatarURL: nil) }
        guard let client = SupabaseManager.client else { return nil }
        return try await client
            .from("profiles")
            .select("id, nickname, avatar_url")
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }
}
