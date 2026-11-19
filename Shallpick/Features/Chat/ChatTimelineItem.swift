import Foundation

/// Source identity keeps a photo comment separate from a message with the same UUID.
nonisolated enum ChatTimelineItem: Hashable, Sendable, Identifiable {
    case message(ChatMessage)
    case photoComment(ChatMessage, commentID: UUID)

    var id: String {
        switch self {
        case .message(let message): "message:\(message.id.uuidString)"
        case .photoComment(_, let commentID): "photo_comment:\(commentID.uuidString)"
        }
    }
}

extension ChatMessage {
    nonisolated var timelineItem: ChatTimelineItem {
        if let sourceCommentID { .photoComment(self, commentID: sourceCommentID) }
        else { .message(self) }
    }

    nonisolated var isPhotoComment: Bool { sourceCommentID != nil }
    nonisolated var timelineID: String { timelineItem.id }
}
