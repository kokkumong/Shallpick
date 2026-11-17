import Foundation
import Supabase

nonisolated struct ChatMessage: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let folderID: UUID
    let userID: UUID
    let body: String
    let createdAt: Date
    /// 첨부한 폴더 사진 (public.photos.id, 고른 순서)
    var photoIDs: [UUID] = []

    enum CodingKeys: String, CodingKey {
        case id
        case folderID = "folder_id"
        case userID = "user_id"
        case body
        case createdAt = "created_at"
        case photoIDs = "photo_ids"
    }

    init(id: UUID, folderID: UUID, userID: UUID, body: String, createdAt: Date, photoIDs: [UUID] = []) {
        self.id = id
        self.folderID = folderID
        self.userID = userID
        self.body = body
        self.createdAt = createdAt
        self.photoIDs = photoIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folderID = try container.decode(UUID.self, forKey: .folderID)
        userID = try container.decode(UUID.self, forKey: .userID)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        photoIDs = try container.decodeIfPresent([UUID].self, forKey: .photoIDs) ?? []
    }
}

/// 채팅방에 보일 멤버 이름/사진
nonisolated struct ChatMember: Decodable, Sendable, Hashable {
    let userID: UUID
    let nickname: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case nickname
        case avatarURL = "avatar_url"
    }
}

/// supabase/migrations 의 public.messages, folder_member_profiles RPC
enum ChatRepository {
    static let maxBodyLength = 1000
    /// 채팅방을 열 때 불러오는 최근 메시지 수
    static let historyLimit = 200
    /// 한 메시지에 붙일 수 있는 사진 수 (DB check 와 같음)
    static let maxPhotos = 30

    private struct NewMessage: Encodable {
        let id: UUID
        let folder_id: UUID
        let body: String
        let photo_ids: [UUID]
    }

    private static var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }
            return client
        }
    }

    /// 최근 메시지 (오래된 것 → 최신 순)
    static func fetchRecent(folderID: UUID) async throws -> [ChatMessage] {
        let latestFirst: [ChatMessage] = try await client
            .from("messages")
            .select()
            .eq("folder_id", value: folderID)
            .order("created_at", ascending: false)
            .limit(historyLimit)
            .execute()
            .value
        return latestFirst.reversed()
    }

    static func fetchMembers(folderID: UUID) async throws -> [ChatMember] {
        try await client
            .rpc("folder_member_profiles", params: ["target_folder_id": folderID])
            .execute()
            .value
    }

    /// id 는 앱에서 만들어 보냅니다. Realtime 으로 같은 메시지가 다시 와도 id 로 합칩니다.
    static func send(id: UUID, folderID: UUID, body: String, photoIDs: [UUID] = []) async throws -> ChatMessage {
        try await client
            .from("messages")
            .insert(NewMessage(id: id, folder_id: folderID, body: body, photo_ids: photoIDs))
            .select()
            .single()
            .execute()
            .value
    }

    struct Subscription {
        /// 이 폴더에 새로 저장된 메시지
        let messages: AsyncStream<ChatMessage>
        /// 다 쓰면(화면을 나가면) 불러서 채널을 정리
        let close: () async -> Void
    }

    /// folderID 가 nil 이면 내가 참여한 모든 폴더의 새 메시지 (RLS 로 걸러짐) — 앱 안 질문 알림용
    static func subscribe(folderID: UUID?) async throws -> Subscription {
        let client = try Self.client
        // SDK 는 같은 이름의 채널을 재사용하므로, 화면을 다시 열거나 다시 시도할 때
        // 이전 구독을 정리하면서 새 구독까지 닫히지 않게 매번 다른 이름을 씁니다.
        let scope = folderID?.uuidString.lowercased() ?? "all"
        let channel = client.channel("folder-chat:\(scope):\(UUID().uuidString.lowercased())")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: folderID.map { .eq("folder_id", value: $0.uuidString.lowercased()) }
        )
        try await channel.subscribeWithError()

        let messages = AsyncStream<ChatMessage> { continuation in
            let task = Task {
                for await action in inserts {
                    do {
                        continuation.yield(try action.decodeRecord(as: ChatMessage.self, decoder: AnyJSON.decoder))
                    } catch {
                        print("[Chat] 실시간 메시지 해석 실패:", error)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return Subscription(messages: messages, close: { await client.removeChannel(channel) })
    }
}
