import Foundation

/// A question's recipient snapshot is the authority; opening a message is not an answer.
nonisolated struct QuestionApproval {
    let recipientIDs: Set<UUID>
    let photoIDs: [UUID]
    private let answers: [UUID: [UUID: QuestionVote]]

    init(messageID: UUID, recipientIDs: [UUID], photoIDs: [UUID], votes: [QuestionVoteRecord]) {
        self.recipientIDs = Set(recipientIDs)
        self.photoIDs = photoIDs
        var answers: [UUID: [UUID: QuestionVote]] = [:]
        for record in votes.sorted(by: { $0.createdAt < $1.createdAt })
            where record.messageID == messageID && self.recipientIDs.contains(record.userID) {
            answers[record.photoID, default: [:]][record.userID] = record.vote
        }
        self.answers = answers
    }

    func voters(for photoID: UUID, vote: QuestionVote) -> Set<UUID> {
        Set((answers[photoID] ?? [:]).filter { $0.value == vote }.map(\.key))
    }

    func pending(for photoID: UUID) -> Set<UUID> {
        recipientIDs.subtracting(Set((answers[photoID] ?? [:]).keys))
    }

    var approvedPhotoIDs: [UUID] {
        guard !recipientIDs.isEmpty else { return [] }
        return photoIDs.filter { voters(for: $0, vote: .like) == recipientIDs }
    }

    var completedRecipientIDs: Set<UUID> {
        guard !photoIDs.isEmpty else { return [] }
        return Set(recipientIDs.filter { user in photoIDs.allSatisfy { answers[$0]?[user] != nil } })
    }
}
