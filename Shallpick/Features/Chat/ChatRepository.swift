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
    /// 질문을 받을 멤버. 비어 있으면 폴더 모두 (보통 채팅)
    var recipientIDs: [UUID] = []
    /// Present only on the read-only chat timeline projection. Never sent to messages.
    var sourceCommentID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case folderID = "folder_id"
        case userID = "user_id"
        case body
        case createdAt = "created_at"
        case photoIDs = "photo_ids"
        case recipientIDs = "recipient_ids"
        case sourceCommentID = "source_comment_id"
    }

    init(
        id: UUID,
        folderID: UUID,
        userID: UUID,
        body: String,
        createdAt: Date,
        photoIDs: [UUID] = [],
        recipientIDs: [UUID] = [],
        sourceCommentID: UUID? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.userID = userID
        self.body = body
        self.createdAt = createdAt
        self.photoIDs = photoIDs
        self.recipientIDs = recipientIDs
        self.sourceCommentID = sourceCommentID
    }

    /// 수달로 받을 사람을 골라 보낸 질문 (보통 채팅은 받을 사람이 비어 있음)
    var isQuestion: Bool { sourceCommentID == nil && !recipientIDs.isEmpty }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folderID = try container.decode(UUID.self, forKey: .folderID)
        userID = try container.decode(UUID.self, forKey: .userID)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        photoIDs = try container.decodeIfPresent([UUID].self, forKey: .photoIDs) ?? []
        recipientIDs = try container.decodeIfPresent([UUID].self, forKey: .recipientIDs) ?? []
        sourceCommentID = try container.decodeIfPresent(UUID.self, forKey: .sourceCommentID)
    }
}

/// 사진 질문을 "확인하러가기"로 확인한 기록 (public.message_checks)
nonisolated struct MessageCheck: Codable, Sendable, Hashable {
    let messageID: UUID
    let userID: UUID
    let checkedAt: Date

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case userID = "user_id"
        case checkedAt = "checked_at"
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
    /// 보통 메시지와 나에게 온 요청만 셉니다. 페이지 크기와 무관한 서버의 전체 개수입니다.
    static func unreadCount(folderID: UUID, userID: UUID, since: Date) async throws -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try await client
            .from("folder_chat_timeline")
            .select("id", head: true, count: .exact)
            .eq("folder_id", value: folderID)
            .neq("user_id", value: userID)
            .gt("created_at", value: formatter.string(from: since))
            .or("recipient_ids.eq.{},recipient_ids.cs.{\(userID.uuidString)}")
            .execute()
            .count ?? 0
    }

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
        let recipient_ids: [UUID]

        // 보통 채팅은 recipient_ids 를 아예 보내지 않음 (DB 기본값 '{}')
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(folder_id, forKey: .folder_id)
            try container.encode(body, forKey: .body)
            try container.encode(photo_ids, forKey: .photo_ids)
            if !recipient_ids.isEmpty {
                try container.encode(recipient_ids, forKey: .recipient_ids)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id, folder_id, body, photo_ids, recipient_ids
        }
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
            .from("folder_chat_timeline")
            .select()
            .eq("folder_id", value: folderID)
            .order("created_at", ascending: false)
            .order("entry_id", ascending: false)
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
    /// recipientIDs 를 주면 그 멤버에게만 가는 질문 (비우면 보통 채팅)
    static func send(
        id: UUID,
        folderID: UUID,
        body: String,
        photoIDs: [UUID] = [],
        recipientIDs: [UUID] = []
    ) async throws -> ChatMessage {
        try await client
            .from("messages")
            .insert(NewMessage(
                id: id,
                folder_id: folderID,
                body: body,
                photo_ids: photoIDs,
                recipient_ids: recipientIDs
            ))
            .select()
            .single()
            .execute()
            .value
    }

    /// 이 폴더 질문들의 확인 기록 (확인한 순서)
    static func fetchChecks(folderID: UUID) async throws -> [MessageCheck] {
        try await client
            .from("message_checks")
            .select("message_id, user_id, checked_at")
            .eq("folder_id", value: folderID)
            .order("checked_at", ascending: true)
            .execute()
            .value
    }

    /// 사진 질문을 확인했다고 남김. 이미 남겼으면 그대로 둠
    static func markChecked(messageID: UUID, folderID: UUID) async throws {
        struct NewCheck: Encodable {
            let message_id: UUID
            let folder_id: UUID
        }
        try await client
            .from("message_checks")
            .upsert(
                NewCheck(message_id: messageID, folder_id: folderID),
                onConflict: "message_id,user_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    struct Subscription {
        /// 이 폴더에 새로 저장된 메시지
        let messages: AsyncStream<ChatMessage>
        /// 새로 남은 질문 확인 기록 (includeChecks 일 때만)
        let checks: AsyncStream<MessageCheck>
        /// Invalidate the projection on comment insert/delete; payloads aren't copied into messages.
        var commentChanges: AsyncStream<Void> = AsyncStream { $0.finish() }
        /// 다 쓰면(화면을 나가면) 불러서 채널을 정리
        let close: () async -> Void
    }

    /// folderID 가 nil 이면 내가 참여한 모든 폴더의 새 메시지 (RLS 로 걸러짐) — 앱 안 질문 알림용
    /// includeChecks: 질문 확인 기록도 받기 (채팅방에서만)
    static func subscribe(folderID: UUID?, includeChecks: Bool = false) async throws -> Subscription {
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
        let checkInserts = includeChecks ? channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_checks",
            filter: folderID.map { .eq("folder_id", value: $0.uuidString.lowercased()) }
        ) : nil
        let commentEvents = channel.postgresChange(
            AnyAction.self, schema: "public", table: "photo_comments"
        )
        try await channel.subscribeWithError()

        return Subscription(
            messages: records(of: inserts, as: ChatMessage.self),
            checks: checkInserts.map { records(of: $0, as: MessageCheck.self) } ?? AsyncStream { $0.finish() },
            commentChanges: invalidations(of: commentEvents),
            close: { await client.removeChannel(channel) }
        )
    }

    private static func invalidations(of changes: AsyncStream<AnyAction>) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in changes { continuation.yield(()) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func records<Record: Decodable & Sendable>(
        of inserts: AsyncStream<InsertAction>,
        as type: Record.Type
    ) -> AsyncStream<Record> {
        AsyncStream<Record> { continuation in
            let task = Task {
                for await action in inserts {
                    do {
                        continuation.yield(try action.decodeRecord(as: Record.self, decoder: AnyJSON.decoder))
                    } catch {
                        print("[Chat] 실시간 \(Record.self) 해석 실패:", error)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
