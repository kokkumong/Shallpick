import Foundation
import Observation
import Supabase

/// 채팅방 하나의 메시지 목록 + 실시간 수신 + 보내기
@Observable
final class ChatStore {
    enum DeliveryState {
        case sending
        case failed
    }

    let folder: Folder
    let myUserID: UUID?

    /// 오래된 것 → 최신 순
    private(set) var messages: [ChatMessage] = []
    /// 내가 보낸 메시지 중 아직 서버에 저장되지 않았거나 실패한 것
    private(set) var deliveryStates: [UUID: DeliveryState] = [:]
    private(set) var members: [UUID: ChatMember] = [:]
    /// 폴더 사진 (최신 순). 첨부 사진을 보여 주고, 채팅방에서 질문에 붙일 사진을 고를 때 씀
    private(set) var folderPhotos: [PhotoItem] = []
    private var photosByID: [UUID: PhotoItem] = [:]
    private(set) var isLoading = true
    private(set) var loadFailed = false

    init(folder: Folder, myUserID: UUID? = PhotoRepository.currentUserID) {
        self.folder = folder
        self.myUserID = myUserID
    }

    /// 미리보기에서는 서버에 붙지 않음
    private var isPreview = false

    /// 화면이 떠 있는 동안 `.task` 에서 실행. 화면을 나가면(Task 취소) 구독을 정리합니다.
    func run() async {
        guard !isPreview else { return }
        isLoading = true
        loadFailed = false

        // 구독을 먼저 열고 기록을 불러와야 그 사이에 온 메시지를 놓치지 않습니다. (중복은 id 로 합침)
        let subscription: ChatRepository.Subscription
        do {
            subscription = try await ChatRepository.subscribe(folderID: folder.id)
        } catch {
            handleLoadError(error)
            return
        }

        do {
            async let history = ChatRepository.fetchRecent(folderID: folder.id)
            async let loadedMembers = ChatRepository.fetchMembers(folderID: folder.id)
            // 사진을 못 불러와도 대화는 보여 줌 (첨부 자리는 빈 카드)
            async let loadedPhotos = try? PhotoRepository.fetch(folderID: folder.id)
            setMembers(try await loadedMembers)
            if let photos = await loadedPhotos { setPhotos(photos) }
            for message in try await history { merge(message, confirmed: true) }
            isLoading = false
        } catch {
            handleLoadError(error)
        }

        for await message in subscription.messages {
            merge(message, confirmed: true)
            if members[message.userID] == nil,
               let reloaded = try? await ChatRepository.fetchMembers(folderID: folder.id) {
                // 새로 들어온 멤버
                setMembers(reloaded)
            }
            if message.photoIDs.contains(where: { photosByID[$0] == nil }) {
                // 방금 올라온 사진이 붙어 옴
                await reloadPhotos()
            }
        }
        await subscription.close()
    }

    /// photos: 질문에 붙일 폴더 사진 (고른 순서)
    func send(_ text: String, photos: [PhotoItem] = []) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let myUserID else { return }
        let attached = Array(photos.filter { $0.folderID == folder.id }.prefix(ChatRepository.maxPhotos))
        for photo in attached where photosByID[photo.id] == nil {
            photosByID[photo.id] = photo
        }
        let message = ChatMessage(
            id: UUID(),
            folderID: folder.id,
            userID: myUserID,
            body: String(body.prefix(ChatRepository.maxBodyLength)),
            createdAt: .now,
            photoIDs: attached.map(\.id)
        )
        merge(message, confirmed: false)
        deliver(message)
    }

    func retry(_ id: UUID) {
        guard deliveryStates[id] == .failed, let message = messages.first(where: { $0.id == id }) else { return }
        deliver(message)
    }

    func member(for userID: UUID) -> ChatMember? {
        members[userID]
    }

    /// 첨부 사진 (지워졌거나 아직 못 불러온 사진은 nil)
    func attachedPhotos(of message: ChatMessage) -> [PhotoItem?] {
        message.photoIDs.map { photosByID[$0] }
    }

    func reloadPhotos() async {
        guard !isPreview, let photos = try? await PhotoRepository.fetch(folderID: folder.id) else { return }
        setPhotos(photos)
    }

    func isMine(_ message: ChatMessage) -> Bool {
        message.userID == myUserID
    }

    // MARK: - Private

    private func deliver(_ message: ChatMessage) {
        deliveryStates[message.id] = .sending
        Task {
            do {
                let saved = try await ChatRepository.send(
                    id: message.id,
                    folderID: message.folderID,
                    body: message.body,
                    photoIDs: message.photoIDs
                )
                merge(saved, confirmed: true)
            } catch {
                print("[Chat] 메시지 보내기 실패:", error)
                deliveryStates[message.id] = .failed
            }
        }
    }

    private func handleLoadError(_ error: Error) {
        guard !(error is CancellationError) else { return }
        print("[Chat] 채팅 불러오기 실패:", error)
        isLoading = false
        loadFailed = messages.isEmpty
    }

    private func setMembers(_ list: [ChatMember]) {
        members = Dictionary(list.map { ($0.userID, $0) }, uniquingKeysWith: { _, new in new })
    }

    private func setPhotos(_ list: [PhotoItem]) {
        folderPhotos = list
        photosByID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 같은 id 가 있으면 새 값으로 바꾸고, 없으면 시간 순서 자리에 끼워 넣습니다.
    /// confirmed: 서버에 저장된 값(조회 / 실시간 / 보내기 응답)
    private func merge(_ message: ChatMessage, confirmed: Bool) {
        if confirmed { deliveryStates[message.id] = nil }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            if !messages.isSorted() { messages.sort { $0.createdAt < $1.createdAt } }
            return
        }
        let index = messages.lastIndex { $0.createdAt <= message.createdAt }.map { $0 + 1 } ?? 0
        messages.insert(message, at: index)
    }
}

#if DEBUG
extension ChatStore {
    func loadPreview(me: UUID) {
        isPreview = true
        let others = [
            ChatMember(userID: UUID(), nickname: "정규호", avatarURL: nil),
            ChatMember(userID: UUID(), nickname: "김승완", avatarURL: nil),
            ChatMember(userID: UUID(), nickname: "신지원", avatarURL: nil),
        ]
        setMembers(others + [ChatMember(userID: me, nickname: "나", avatarURL: nil)])
        let photos = (1...4).map { index in
            PhotoItem(
                id: UUID(),
                folderID: folder.id,
                uploaderID: me,
                storagePath: "\(folder.id)/\(index).jpg",
                createdAt: .now,
                url: URL(string: "https://picsum.photos/seed/chat\(index)/300/400")
            )
        }
        setPhotos(photos)
        let start = Date.now.addingTimeInterval(-60 * 60 * 26)
        let script: [(UUID, String, TimeInterval, [PhotoItem])] = [
            (others[0].userID, "안녕하세요~~", 0, []),
            (others[1].userID, "구름이 귀여워", 60, [photos[0]]),
            (me, "우와!", 120, []),
            (me, "괜찮아요?", 130, Array(photos[1...3])),
            (others[2].userID, "이거 인스타에 올려도 되나요?", 60 * 60 * 25, Array(photos[0...2])),
            (me, "귀여워..", 60 * 60 * 25 + 300, [photos[3]]),
            (me, "좋아요", 60 * 60 * 25 + 700, []),
        ]
        for (userID, body, offset, attached) in script {
            merge(
                ChatMessage(
                    id: UUID(),
                    folderID: folder.id,
                    userID: userID,
                    body: body,
                    createdAt: start.addingTimeInterval(offset),
                    photoIDs: attached.map(\.id)
                ),
                confirmed: true
            )
        }
        isLoading = false
    }
}
#endif

private extension [ChatMessage] {
    func isSorted() -> Bool {
        zip(self, dropFirst()).allSatisfy { $0.createdAt <= $1.createdAt }
    }
}
