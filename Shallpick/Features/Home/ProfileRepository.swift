import Foundation
import UIKit
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
        if DemoStore.shared.isActive {
            DemoStore.shared.nickname = nickname
            return Profile(id: userID, nickname: nickname, avatarURL: nil)
        }
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

    /// 프로필 사진 버킷 (supabase/migrations 의 avatars, 공개)
    private static let avatarBucket = "avatars"
    /// 프로필 사진은 가운데를 정사각형으로 잘라 이 크기로 줄여 올림
    nonisolated private static let avatarSide: CGFloat = 512

    /// 새 프로필 사진을 올리고 profiles.avatar_url 을 바꿉니다. 예전에 올린 사진 파일은 지웁니다.
    static func updateAvatar(_ image: UIImage, userID: UUID, previousURL: String?) async throws -> Profile {
        guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }
        let data = try await Task.detached(priority: .userInitiated) {
            guard let data = image.squareCropped(side: avatarSide).jpegData(compressionQuality: 0.85)
            else { throw AvatarError.unreadableImage }
            return data
        }.value

        let folder = userID.uuidString.lowercased()
        // 파일 이름을 매번 새로 지어야 AsyncImage/CDN 캐시가 예전 사진을 보여주지 않음
        let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
        let storage = client.storage.from(avatarBucket)
        try await storage.upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        let publicURL = try storage.getPublicURL(path: path).absoluteString

        let profile: Profile = try await client
            .from("profiles")
            .update(["avatar_url": publicURL])
            .eq("id", value: userID)
            .select("id, nickname, avatar_url")
            .single()
            .execute()
            .value

        await removeUploadedAvatar(previousURL, userID: userID, keeping: path)
        return profile
    }

    /// 프로필 사진을 지우고 기본 이미지(수달)로 돌립니다.
    static func resetAvatar(userID: UUID, previousURL: String?) async throws -> Profile {
        guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }
        let empty: [String: String?] = ["avatar_url": nil]
        let profile: Profile = try await client
            .from("profiles")
            .update(empty)
            .eq("id", value: userID)
            .select("id, nickname, avatar_url")
            .single()
            .execute()
            .value
        await removeUploadedAvatar(previousURL, userID: userID)
        return profile
    }

    /// 우리 버킷에 올렸던 내 사진만 정리 (카카오 프로필 주소 등은 그대로 둠). 실패해도 무시.
    private static func removeUploadedAvatar(_ url: String?, userID: UUID, keeping kept: String? = nil) async {
        guard let client = SupabaseManager.client,
              let url, let range = url.range(of: "/\(avatarBucket)/") else { return }
        let path = String(url[range.upperBound...])
        guard path.hasPrefix(userID.uuidString.lowercased() + "/"), path != kept else { return }
        _ = try? await client.storage.from(avatarBucket).remove(paths: [path])
    }

    enum AvatarError: LocalizedError {
        case unreadableImage
        var errorDescription: String? { "사진을 읽을 수 없어요. 다른 사진을 골라 주세요." }
    }

    static func fetch(userID: UUID) async throws -> Profile? {
        if DemoStore.shared.isActive { return Profile(id: userID, nickname: DemoStore.shared.nickname, avatarURL: nil) }
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

private extension UIImage {
    /// 가운데를 정사각형으로 잘라 side×side 로 다시 그림 (방향 정보도 여기서 반영됨)
    nonisolated func squareCropped(side: CGFloat) -> UIImage {
        let shortest = min(size.width, size.height)
        let target = min(side, shortest)
        let scale = target / shortest
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            draw(in: CGRect(
                x: (target - drawSize.width) / 2,
                y: (target - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
    }
}
