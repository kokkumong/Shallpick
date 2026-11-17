import Foundation
import Supabase

/// 프로필 메뉴의 알림 한 줄
/// - 안 읽은 채팅: 폴더마다 한 줄로 묶어 "[폴더] 새 메세지 N개"
/// - 나에게 온 질문: 한 건씩 "[폴더] 현서님이 사진 3장에 대한 질문을 올렸어요! …" (앱 밖 알림과 같은 문구)
nonisolated struct NotificationItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable {
        case unreadChats(count: Int)
        case question(text: String)
    }

    let id: String
    let folder: Folder
    let kind: Kind
    /// 묶음이면 가장 최근 메시지 시각
    let createdAt: Date
    /// 그 폴더 채팅을 마지막으로 본 뒤에 온 것
    let isUnread: Bool

    var text: String {
        switch kind {
        case let .unreadChats(count):
            "새 메세지 \(count >= 100 ? "100+" : "\(count)")개"
        case let .question(text):
            text
        }
    }
}

/// 따로 저장하지 않고 public.messages 와 이 기기에 저장한 "폴더 채팅을 마지막으로 본 시각"으로 만듭니다.
/// 앱 밖 알림과 같은 기준: 내가 보낸 것은 빼고, 질문은 받을 사람으로 고른 멤버에게만 보입니다.
enum NotificationHistory {
    /// 질문은 최근 이만큼까지 (읽은 것도 내역으로 남김)
    static let questionLimit = 30

    static func fetch(folders: [Folder], userID: UUID) async throws -> [NotificationItem] {
        guard !folders.isEmpty else { return [] }
        guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }

        let readState = NotificationReadState(userID: userID)
        async let questions = fetchQuestions(client: client, folders: folders, userID: userID, readState: readState)
        async let chats = fetchUnreadChats(client: client, folders: folders, userID: userID, readState: readState)
        return try await (questions + chats).sorted { $0.createdAt > $1.createdAt }
    }

    private static func fetchQuestions(
        client: SupabaseClient,
        folders: [Folder],
        userID: UUID,
        readState: NotificationReadState
    ) async throws -> [NotificationItem] {
        let messages: [ChatMessage] = try await client
            .from("messages")
            .select()
            .in("folder_id", values: folders.map(\.id))
            .neq("user_id", value: userID)
            // 받을 사람에 내가 들어 있는 질문만
            .filter("recipient_ids", operator: "cs", value: "{\(userID.uuidString)}")
            .order("created_at", ascending: false)
            .limit(questionLimit)
            .execute()
            .value

        let nicknames = await nicknames(folderIDs: Set(messages.map(\.folderID)))
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return messages.compactMap { message in
            guard let folder = foldersByID[message.folderID] else { return nil }
            let nickname = nicknames[message.folderID]?[message.userID] ?? "샬픽 사용자"
            return NotificationItem(
                id: "question-\(message.id)",
                folder: folder,
                kind: .question(text: questionText(message, senderNickname: nickname)),
                createdAt: message.createdAt,
                isUnread: message.createdAt > readState.lastRead(folderID: folder.id)
            )
        }
    }

    /// 사진을 골라 보낸 질문은 앱 밖 알림 문구 그대로, 글만 있는 질문은 누가 물었는지 붙여서
    static func questionText(_ message: ChatMessage, senderNickname: String) -> String {
        if message.photoIDs.isEmpty {
            return "\(senderNickname)님의 질문: \(message.body.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return LocalNotifications.body(for: message, senderNickname: senderNickname)
    }

    /// 폴더마다 마지막으로 본 뒤에 온 보통 채팅 수 (질문은 위에서 따로)
    private static func fetchUnreadChats(
        client: SupabaseClient,
        folders: [Folder],
        userID: UUID,
        readState: NotificationReadState
    ) async throws -> [NotificationItem] {
        struct Row: Decodable { let created_at: Date }

        return try await withThrowingTaskGroup(of: NotificationItem?.self) { group in
            for folder in folders {
                let since = timestamp(readState.lastRead(folderID: folder.id))
                group.addTask {
                    let response: PostgrestResponse<[Row]> = try await client
                        .from("messages")
                        .select("created_at", count: .exact)
                        .eq("folder_id", value: folder.id)
                        .neq("user_id", value: userID)
                        .eq("recipient_ids", value: "{}")
                        .gt("created_at", value: since)
                        .order("created_at", ascending: false)
                        .limit(1)
                        .execute()
                    guard let count = response.count, count > 0, let latest = response.value.first else { return nil }
                    return NotificationItem(
                        id: "chats-\(folder.id)",
                        folder: folder,
                        kind: .unreadChats(count: count),
                        createdAt: latest.created_at,
                        isUnread: true
                    )
                }
            }
            var items: [NotificationItem] = []
            for try await item in group {
                if let item { items.append(item) }
            }
            return items
        }
    }

    /// PostgREST 비교용 시각 (밀리초까지)
    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// 폴더별 멤버 닉네임 (폴더마다 한 번씩, 동시에)
    private static func nicknames(folderIDs: Set<UUID>) async -> [UUID: [UUID: String]] {
        await withTaskGroup(of: (UUID, [UUID: String]).self) { group in
            for folderID in folderIDs {
                group.addTask {
                    let members = (try? await ChatRepository.fetchMembers(folderID: folderID)) ?? []
                    let byID = Dictionary(members.map { ($0.userID, $0.nickname) }, uniquingKeysWith: { first, _ in first })
                    return (folderID, byID)
                }
            }
            var result: [UUID: [UUID: String]] = [:]
            for await (folderID, byID) in group {
                result[folderID] = byID
            }
            return result
        }
    }
}

/// 이 기기에 저장하는 읽음 기록 (계정마다 따로)
/// - 폴더 채팅을 마지막으로 본 시각: 그 뒤에 온 것이 "안 읽은" 알림
/// - 프로필 메뉴를 마지막으로 연 시각: 그 뒤에 새로 쌓인 게 있으면 프로필에 빨간 점
nonisolated struct NotificationReadState: Sendable {
    let userID: UUID

    private var defaults: UserDefaults { .standard }
    private var foldersKey: String { "notifications.lastRead.\(userID)" }
    private var menuKey: String { "notifications.menuSeen.\(userID)" }
    private var baselineKey: String { "notifications.baseline.\(userID)" }

    /// 처음 쓰기 시작한 시각. 그 전에 온 메시지까지 한꺼번에 "안 읽음"으로 뜨지 않게
    private var baseline: Date {
        if let saved = defaults.object(forKey: baselineKey) as? Date { return saved }
        let now = Date.now
        defaults.set(now, forKey: baselineKey)
        return now
    }

    func lastRead(folderID: UUID) -> Date {
        let saved = defaults.dictionary(forKey: foldersKey)?[folderID.uuidString] as? Date
        return saved ?? baseline
    }

    func markRead(folderID: UUID, at date: Date = .now) {
        var all = defaults.dictionary(forKey: foldersKey) ?? [:]
        all[folderID.uuidString] = date
        defaults.set(all, forKey: foldersKey)
    }

    var menuSeenAt: Date {
        defaults.object(forKey: menuKey) as? Date ?? baseline
    }

    func markMenuSeen(at date: Date = .now) {
        defaults.set(date, forKey: menuKey)
    }

    /// 메뉴를 마지막으로 연 뒤에 새로 쌓인 안 읽은 알림이 있는지
    func hasNew(in items: [NotificationItem]) -> Bool {
        let seen = menuSeenAt
        return items.contains { $0.isUnread && $0.createdAt > seen }
    }
}
