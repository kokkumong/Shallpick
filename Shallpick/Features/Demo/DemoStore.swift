import Foundation
import Observation

/// Demo builds never create a backend client. All changes live only in this process.
@Observable
final class DemoStore {
    static let shared = DemoStore()
    static var isAvailable: Bool {
        #if SHALLPICK_DEMO
        true
        #else
        false
        #endif
    }

    let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let friendID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private(set) var isActive = false
    private(set) var generation = 0
    private(set) var folders: [Folder] = []
    private var photoLists: [UUID: [PhotoItem]] = [:]
    private var conversations: [UUID: [ChatMessage]] = [:]
    private var pendingInvite: Folder?
    var questionVotes: [QuestionVoteRecord] = []
    var questionPins: [QuestionPin] = []
    var photoReactions: [PhotoReaction] = []
    var photoComments: [PhotoComment] = []
    var messageChecks: [MessageCheck] = []

    private init() { reset() }

    func begin() {
        guard Self.isAvailable else { return }
        reset()
        isActive = true
    }

    func end() {
        isActive = false
        reset()
    }

    func reset() {
        generation += 1
        photoLists = [:]
        conversations = [:]
        questionVotes = []
        questionPins = []
        photoReactions = []
        photoComments = []
        messageChecks = []
        folders = [
            Folder(id: UUID(), name: "주말 나들이", ownerID: userID, inviteCode: "WEEKND", memberNames: ["나", "하늘", "민서"]),
            Folder(id: UUID(), name: "다음 여행", ownerID: friendID, inviteCode: "TRAVEL", memberNames: ["나", "하늘"])
        ]
        for (index, folder) in folders.enumerated() {
            photoLists[folder.id] = (0..<8).map { makePhoto(folderID: folder.id, index: $0 + index * 2) }
            conversations[folder.id] = [
                ChatMessage(id: UUID(), folderID: folder.id, userID: friendID,
                            body: "이 사진 인스타 스토리에 올려도 괜찮을까?", createdAt: Date().addingTimeInterval(-600),
                            photoIDs: Array((photoLists[folder.id] ?? []).prefix(3).map(\.id)), recipientIDs: [userID]),
                ChatMessage(id: UUID(), folderID: folder.id, userID: userID,
                            body: "같이 보고 골라보자!", createdAt: Date().addingTimeInterval(-540))
            ]
            let samplePhotos = Array(photos(in: folder.id).prefix(3))
            let ownQuestion = ChatMessage(id: UUID(), folderID: folder.id, userID: userID,
                body: "[샘플 결과] 이 사진 같이 올려도 돼?", createdAt: Date().addingTimeInterval(-500),
                photoIDs: samplePhotos.map(\.id), recipientIDs: [friendID])
            conversations[folder.id, default: []].append(ownQuestion)
            messageChecks.append(MessageCheck(messageID: ownQuestion.id, userID: friendID, checkedAt: .now))
            for (offset, photo) in samplePhotos.enumerated() {
                questionVotes.append(QuestionVoteRecord(messageID: ownQuestion.id, photoID: photo.id,
                    userID: friendID, vote: offset == 1 ? .dislike : .like, createdAt: .now))
            }
            if let photo = samplePhotos.first {
                questionPins.append(QuestionPin(id: UUID(), messageID: ownQuestion.id, photoID: photo.id,
                    userID: friendID, x: 0.55, y: 0.4, body: "[샘플 의견] 여기는 조금 잘라주면 좋겠어", createdAt: .now))
            }
        }
        pendingInvite = Folder(id: UUID(), name: "친구의 초대", ownerID: friendID, inviteCode: "DEMO26", memberNames: ["나", "하늘"])
    }

    var members: [ChatMember] {
        [ChatMember(userID: userID, nickname: "나", avatarURL: nil),
         ChatMember(userID: friendID, nickname: "하늘", avatarURL: nil)]
    }

    func photos(in folderID: UUID) -> [PhotoItem] { photoLists[folderID] ?? [] }
    func messages(in folderID: UUID) -> [ChatMessage] { conversations[folderID] ?? [] }

    func create(name: String) -> Folder {
        let folder = Folder(id: UUID(), name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(FolderRepository.maxNameLength)),
                            ownerID: userID, inviteCode: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)), memberNames: ["나"])
        folders.insert(folder, at: 0)
        return folder
    }

    func join(code: String) throws -> Folder {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let folder = folders.first(where: { $0.inviteCode == code }) { return folder }
        guard let folder = pendingInvite, folder.inviteCode == code else { throw FolderRepository.FolderError.invalidInviteCode }
        folders.insert(folder, at: 0)
        photoLists[folder.id] = (0..<4).map { makePhoto(folderID: folder.id, index: $0) }
        return folder
    }

    func addSamplePhotos(to folderID: UUID) {
        let newPhotos = (0..<3).map { makePhoto(folderID: folderID, index: $0 + photos(in: folderID).count) }
        photoLists[folderID, default: []].insert(contentsOf: newPhotos, at: 0)
    }

    func send(id: UUID, folderID: UUID, body: String, photoIDs: [UUID], recipientIDs: [UUID] = []) -> ChatMessage {
        let allowed = Set(photos(in: folderID).map(\.id))
        let message = ChatMessage(id: id, folderID: folderID, userID: userID,
                                  body: String(body.prefix(ChatRepository.maxBodyLength)), createdAt: .now,
                                  photoIDs: Array(photoIDs.filter { allowed.contains($0) }.prefix(ChatRepository.maxPhotos)),
                                  recipientIDs: recipientIDs)
        if let index = conversations[folderID]?.firstIndex(where: { $0.id == id }) {
            conversations[folderID]?[index] = message
        } else {
            conversations[folderID, default: []].append(message)
        }
        return message
    }

    func deletePhotos(_ photos: [PhotoItem]) {
        let ids = Set(photos.filter { $0.uploaderID == userID }.map(\.id))
        for folderID in Array(photoLists.keys) { photoLists[folderID]?.removeAll { ids.contains($0.id) } }
    }

    func markChecked(messageID: UUID) {
        guard !messageChecks.contains(where: { $0.messageID == messageID && $0.userID == userID }) else { return }
        messageChecks.append(MessageCheck(messageID: messageID, userID: userID, checkedAt: .now))
    }

    func setVote(_ vote: QuestionVote, messageID: UUID, photoID: UUID) {
        questionVotes.removeAll { $0.messageID == messageID && $0.photoID == photoID && $0.userID == userID }
        questionVotes.append(QuestionVoteRecord(messageID: messageID, photoID: photoID, userID: userID, vote: vote, createdAt: .now))
    }

    /// An explicit sample event, never presented as a real person's response.
    func sampleQuestion() -> QuestionAlert? {
        guard let folder = folders.last else { return nil }
        let photos = Array(photos(in: folder.id).prefix(2))
        let message = ChatMessage(id: UUID(), folderID: folder.id, userID: friendID,
                                  body: "[샘플 질문] 이 사진 같이 올려도 괜찮을까?", createdAt: .now, photoIDs: photos.map(\.id))
        conversations[folder.id, default: []].append(message)
        return QuestionAlert(id: message.id, folder: folder, askerNickname: "하늘", question: message.body, photoURLs: photos.compactMap(\.url))
    }

    private func makePhoto(folderID: UUID, index: Int) -> PhotoItem {
        PhotoItem(id: UUID(), folderID: folderID, uploaderID: index.isMultiple(of: 2) ? userID : friendID,
                  storagePath: "sample-\(index)", createdAt: Date().addingTimeInterval(Double(-index * 60)),
                  url: URL(string: "demo-asset:///DemoPhoto\(index % 4 + 1)"))
    }
}
