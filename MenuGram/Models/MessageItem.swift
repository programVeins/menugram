import Foundation
import TDLibKit

enum MessageContentType: Equatable {
    case text
    case voiceNote(fileId: Int, duration: Int, waveform: Data)
    case photo
    case document
    case sticker
    case unsupported
}

struct MessageItem: Identifiable, Equatable {
    let id: Int64
    let chatId: Int64
    let isOutgoing: Bool
    var textContent: String
    let date: Foundation.Date
    let senderName: String
    let contentType: MessageContentType

    init(from message: Message) {
        self.id = message.id
        self.chatId = message.chatId
        self.isOutgoing = message.isOutgoing
        self.date = Foundation.Date(timeIntervalSince1970: TimeInterval(message.date))

        switch message.content {
        case .messageText(let text):
            self.textContent = text.text.text
            self.contentType = .text
        case .messageVoiceNote(let voiceMsg):
            let duration = voiceMsg.voiceNote.duration
            let caption = voiceMsg.caption.text
            self.textContent = caption.isEmpty ? "Voice message (\(duration)s)" : caption
            self.contentType = .voiceNote(
                fileId: voiceMsg.voiceNote.voice.id,
                duration: duration,
                waveform: voiceMsg.voiceNote.waveform
            )
        case .messagePhoto(let photo):
            self.textContent = photo.caption.text.isEmpty ? "[Photo]" : photo.caption.text
            self.contentType = .photo
        case .messageDocument(let doc):
            self.textContent = "[Document: \(doc.document.fileName)]"
            self.contentType = .document
        case .messageSticker(let sticker):
            self.textContent = sticker.sticker.emoji
            self.contentType = .sticker
        default:
            self.textContent = "[Unsupported message]"
            self.contentType = .unsupported
        }

        switch message.senderId {
        case .messageSenderUser:
            self.senderName = message.isOutgoing ? "You" : "Bot"
        case .messageSenderChat:
            self.senderName = "Channel"
        }
    }
}
