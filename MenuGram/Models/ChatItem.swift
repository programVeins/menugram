import Foundation
import TDLibKit

struct ChatItem: Identifiable, Equatable {
    let id: Int64
    let title: String
    var lastMessagePreview: String
    var lastMessageDate: Foundation.Date
    var unreadCount: Int
    /// File ID for the small (160x160) profile photo, if available
    var photoFileId: Int?
    /// Local path to the downloaded profile photo
    var photoLocalPath: String?

    init(from chat: Chat) {
        self.id = chat.id
        self.title = chat.title
        self.unreadCount = chat.unreadCount
        self.photoFileId = chat.photo?.small.id
        if let photo = chat.photo?.small, photo.local.isDownloadingCompleted {
            self.photoLocalPath = photo.local.path
        }

        if let lastMsg = chat.lastMessage,
           case .messageText(let text) = lastMsg.content {
            self.lastMessagePreview = String(text.text.text.prefix(60))
        } else {
            self.lastMessagePreview = ""
        }

        if let lastMsg = chat.lastMessage {
            self.lastMessageDate = Foundation.Date(timeIntervalSince1970: TimeInterval(lastMsg.date))
        } else {
            self.lastMessageDate = Foundation.Date.distantPast
        }
    }
}
