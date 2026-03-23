import SwiftUI

@main
struct menugramApp: App {
    @State private var telegramService = TelegramService()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(telegramService)
                .frame(width: AppConstants.popoverWidth, height: AppConstants.popoverHeight)
        } label: {
            Image(systemName: "paperplane.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
