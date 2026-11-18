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
    /// 닉네임 최대 글자 수
    static let maxNicknameLength = 20

    /// 본인 닉네임 바꾸기 (RLS "본인 프로필 수정")
    static func updateNickname(_ nickname: String, userID: UUID) async throws -> Profile {
        guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }
        return try await client
            .from("profiles")
            .update(["nickname": nickname])
            .eq("id", value: userID)
            .select("id, nickname, avatar_url")
            .single()
            .execute()
            .value
    }

    static func fetch(userID: UUID) async throws -> Profile? {
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
