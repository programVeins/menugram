import SwiftUI

struct PhoneInputView: View {
    @Environment(TelegramService.self) private var telegram
    @State private var phoneNumber: String = ""
    @State private var isSubmitting: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            TextField("Phone number with country code", text: $phoneNumber)
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
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(phoneNumber.isEmpty || isSubmitting)
            .keyboardShortcut(.return, modifiers: [])
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !phoneNumber.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await telegram.sendPhoneNumber(phoneNumber)
            isSubmitting = false
        }
    }
}
