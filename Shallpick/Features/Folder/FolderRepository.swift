import Foundation
import Supabase

nonisolated struct Folder: Decodable, Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let ownerID: UUID
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerID = "owner_id"
        case inviteCode = "invite_code"
    }
}

/// supabase/migrations 의 public.folders, create_folder / join_folder RPC
enum FolderRepository {
    enum FolderError: LocalizedError {
        case notConfigured
        case invalidInviteCode

        var errorDescription: String? {
            switch self {
            case .notConfigured: "서버 설정이 없어요. Config/Secrets.xcconfig 를 확인해 주세요."
            case .invalidInviteCode: "코드를 다시 확인해 주세요."
            }
        }
    }

    static let maxNameLength = 30

    static func create(name: String) async throws -> Folder {
        guard let client = SupabaseManager.client else { throw FolderError.notConfigured }
        return try await client
            .rpc("create_folder", params: ["folder_name": name])
            .execute()
            .value
    }

    static func join(code: String) async throws -> Folder {
        guard let client = SupabaseManager.client else { throw FolderError.notConfigured }
        do {
            return try await client
                .rpc("join_folder", params: ["code": code])
                .execute()
                .value
        } catch let error as PostgrestError where error.message.contains("invalid_invite_code") {
            throw FolderError.invalidInviteCode
        }
    }
}

/// 초대 링크: shallpick://join?code=ABC123 (QR 로 찍으면 앱이 열리고 코드가 채워짐)
enum FolderInviteLink {
    static let scheme = "shallpick"

    static func url(code: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "join"
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url!
    }

    static func code(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "join" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "code" }?
            .value
    }
}
