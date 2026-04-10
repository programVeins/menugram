import SwiftUI

struct MessageBubbleView: View {
    let message: MessageItem

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 48) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                messageContent

                Text(message.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .foregroundStyle(
                        message.isOutgoing ?
                        LinearGradient(colors: [.cyan.opacity(0.7), .blue.opacity(0.7)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.gray.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        )
            )
            .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
            

            if !message.isOutgoing { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.contentType {
        case .voiceNote(let fileId, let duration, let waveform):
            VoiceNoteView(fileId: fileId, duration: duration, waveform: waveform)
                .frame(minWidth: 180)
        default:
            Text(message.textContent)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
