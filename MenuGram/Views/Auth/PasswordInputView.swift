import SwiftUI

struct PasswordInputView: View {
    @Environment(TelegramService.self) private var telegram
    let hint: String
    @State private var password: String = ""
    @State private var isSubmitting: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Two-Step Verification")
                .font(.subheadline.bold())

            if !hint.isEmpty {
                Text("Hint: \(hint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField("Password", text: $password)
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
                    Text("Submit")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || isSubmitting)
            .keyboardShortcut(.return, modifiers: [])
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !password.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await telegram.sendPassword(password)
            isSubmitting = false
        }
    }
}
