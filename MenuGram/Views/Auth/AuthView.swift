import SwiftUI

struct AuthView: View {
    @Environment(TelegramService.self) private var telegram

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                Text("MenuGram")
                    .font(.title2.bold())
                Text("Sign in to Telegram")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Auth step
            Group {
                switch telegram.authState {
                case .waitingForPhone:
                    PhoneInputView()
                case .waitingForCode(let codeInfo):
                    CodeInputView(codeInfo: codeInfo)
                case .waitingForPassword(let hint):
                    PasswordInputView(hint: hint)
                case .error(let message):
                    ErrorStateView(message: message)
                default:
                    ProgressView()
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorStateView: View {
    @Environment(TelegramService.self) private var telegram
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                telegram.stop()
                telegram.authState = .loading
                telegram.start()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }
}
