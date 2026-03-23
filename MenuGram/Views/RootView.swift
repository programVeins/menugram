import SwiftUI

struct RootView: View {
    @Environment(TelegramService.self) private var telegram

    var body: some View {
        Group {
            switch telegram.authState {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Connecting...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .waitingForPhone, .waitingForCode, .waitingForPassword, .error:
                AuthView()

            case .ready:
                if telegram.currentChatId != nil {
                    ChatDetailView()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading chat...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            telegram.start()
        }
    }
}
