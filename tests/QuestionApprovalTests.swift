import Foundation

@main struct QuestionApprovalTests {
    static func main() {
        let message = UUID(), otherMessage = UUID(), a = UUID(), b = UUID(), outsider = UUID()
        let p = UUID(), q = UUID()
        func record(_ photo: UUID, _ user: UUID, _ vote: QuestionVote, time: Double = 0, id: UUID? = nil) -> QuestionVoteRecord {
            QuestionVoteRecord(messageID: id ?? message, photoID: photo, userID: user, vote: vote, createdAt: Date(timeIntervalSince1970: time))
        }
        func summary(_ recipients: [UUID], _ photos: [UUID], _ votes: [QuestionVoteRecord]) -> QuestionApproval {
            QuestionApproval(messageID: message, recipientIDs: recipients, photoIDs: photos, votes: votes)
        }
        assert(summary([a], [p], [record(p,a,.like)]).approvedPhotoIDs == [p])
        assert(summary([a,b], [p], [record(p,a,.like)]).approvedPhotoIDs.isEmpty)
        assert(summary([a,b], [p], [record(p,a,.like)]).pending(for: p) == [b])
        assert(summary([a,b], [p], [record(p,a,.like),record(p,b,.dislike)]).approvedPhotoIDs.isEmpty)
        let agreed = summary([a,b], [p,q], [record(p,a,.like),record(p,b,.like),record(q,a,.like),record(q,b,.dislike)])
        assert(agreed.approvedPhotoIDs == [p])
        assert(agreed.completedRecipientIDs == [a,b])
        assert(summary([], [p], [record(p,a,.like)]).approvedPhotoIDs.isEmpty)
        assert(summary([a], [], []).completedRecipientIDs.isEmpty)
        assert(summary([a], [p], [record(p,outsider,.like)]).approvedPhotoIDs.isEmpty)
        assert(summary([a], [p], [record(p,a,.like,id:otherMessage)]).approvedPhotoIDs.isEmpty)
        assert(summary([a], [p], [record(p,a,.like),record(p,a,.dislike,time:1)]).approvedPhotoIDs.isEmpty)
        assert(summary([a,a], [p], [record(p,a,.like)]).approvedPhotoIDs == [p])
        assert(summary([a], [p,q], [record(p,a,.like)]).completedRecipientIDs.isEmpty)
        print("QuestionApproval: 13 scenarios passed")
    }
}
