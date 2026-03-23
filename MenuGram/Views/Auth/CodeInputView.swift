import SwiftUI

struct CodeInputView: View {
    @Environment(TelegramService.self) private var telegram
    let codeInfo: String
    @State private var code: String = ""
    @State private var isSubmitting: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(codeInfo)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Verification code", text: $code)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { submit() }
                .disabled(isSubmitting)

            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Verify")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.isEmpty || isSubmitting)
            .keyboardShortcut(.return, modifiers: [])
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !code.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await telegram.sendAuthCode(code)
            isSubmitting = false
        }
    }
}
