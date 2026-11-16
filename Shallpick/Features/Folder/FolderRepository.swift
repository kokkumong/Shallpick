import Foundation
import Supabase

nonisolated struct Folder: Decodable, Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let ownerID: UUID
    let inviteCode: String
    /// my_folders() 에서만 채워짐. 참여한 순서.
    var memberNames: [String] = []
    /// 폴더 표지에 보일 사진. 사진 기능이 생기면 채웁니다.
    var coverPhotoURLs: [URL] = []

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerID = "owner_id"
        case inviteCode = "invite_code"
        case memberNames = "member_names"
    }

    init(id: UUID, name: String, ownerID: UUID, inviteCode: String, memberNames: [String] = []) {
        self.id = id
        self.name = name
        self.ownerID = ownerID
        self.inviteCode = inviteCode
        self.memberNames = memberNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ownerID = try container.decode(UUID.self, forKey: .ownerID)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        memberNames = try container.decodeIfPresent([String].self, forKey: .memberNames) ?? []
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

    /// 내가 참여한 폴더 (최근 참여 순)
    static func fetchMine() async throws -> [Folder] {
        guard let client = SupabaseManager.client else { throw FolderError.notConfigured }
        return try await client
            .rpc("my_folders")
            .execute()
            .value
    }

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
