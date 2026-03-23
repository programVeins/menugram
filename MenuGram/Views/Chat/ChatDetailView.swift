import SwiftUI
import TDLibKit

struct ChatDetailView: View {
    @Environment(TelegramService.self) private var telegram

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let photoPath = currentChat?.photoLocalPath,
                   let nsImage = NSImage(contentsOfFile: photoPath) {
                    ZStack {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .blur(radius: 5)
                            .opacity(0.3)
                            .offset(y: 4)
                        
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    }
                } else {
                    Circle()
                        .fill(.blue.gradient)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text(String(currentChatTitle.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentChatTitle)
                        .font(.headline)

                    if let actionText = chatActionText {
                        ShimmerText(actionText)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if telegram.isLoadingOlderMessages {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }

                        ForEach(Array(telegram.currentChatMessages.enumerated()), id: \.element.id) { index, message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .onAppear {
                                    if index == 0,
                                       telegram.didInitialLoad,
                                       telegram.hasOlderMessages,
                                       !telegram.isLoadingOlderMessages {
                                        Task { await telegram.loadOlderMessages() }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: telegram.currentChatMessages.last?.id) { _, newId in
                    if let id = newId {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            MessageInputView()
                .padding(8)
        }
        .overlay {
            if telegram.isLoadingMessages {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var currentChat: ChatItem? {
        guard let chatId = telegram.currentChatId else { return nil }
        return telegram.chats.first(where: { $0.id == chatId })
    }

    private var currentChatTitle: String {
        currentChat?.title ?? "Chat"
    }

    private var chatActionText: String? {
        guard let action = telegram.currentChatAction else { return nil }
        switch action {
        case .chatActionTyping:
            return "typing..."
        case .chatActionRecordingVoiceNote:
            return "recording voice..."
        case .chatActionUploadingVoiceNote:
            return "sending voice..."
        case .chatActionRecordingVideo:
            return "recording video..."
        case .chatActionUploadingVideo:
            return "sending video..."
        case .chatActionUploadingPhoto:
            return "sending photo..."
        case .chatActionUploadingDocument:
            return "sending file..."
        case .chatActionChoosingSticker:
            return "choosing sticker..."
        case .chatActionRecordingVideoNote:
            return "recording video message..."
        case .chatActionUploadingVideoNote:
            return "sending video message..."
        case .chatActionChoosingLocation:
            return "choosing location..."
        case .chatActionChoosingContact:
            return "choosing contact..."
        default:
            return nil
        }
    }
}
// MARK: - Shimmer Text
private struct ShimmerText: View {
    let text: String
    @State private var offset: CGFloat = -1

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.blue.opacity(0.4))
            .overlay {
                GeometryReader { geo in
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .mask {
                            LinearGradient(
                                colors: [.clear, .white, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: offset * geo.size.width)
                        }
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    offset = 1.5
                }
            }
    }
}

#Preview {
    ChatDetailView()
}
