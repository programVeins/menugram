import Foundation

enum AppConstants {
    // MARK: - Telegram API Credentials
    // Set TELEGRAM_API_ID, TELEGRAM_API_HASH, and BOT_NAME as environment variables
    // in the Xcode scheme (Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables)
    static let apiId: Int = Int(ProcessInfo.processInfo.environment["TELEGRAM_API_ID"] ?? "") ?? 0
    static let apiHash: String = ProcessInfo.processInfo.environment["TELEGRAM_API_HASH"] ?? ""
    static let botName: String = ProcessInfo.processInfo.environment["BOT_NAME"] ?? "<YourBotContactName>"

    // MARK: - App Info
    static let appVersion: String = "1.0"
    static let deviceModel: String = "macOS"
    static let systemLanguageCode: String = Locale.current.language.languageCode?.identifier ?? "en"

    // MARK: - TDLib Storage
    static var databaseDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tdlibDir = appSupport.appendingPathComponent("com.sabesh.menugram/tdlib", isDirectory: true)
        try? FileManager.default.createDirectory(at: tdlibDir, withIntermediateDirectories: true)
        return tdlibDir.path
    }

    static var filesDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let filesDir = appSupport.appendingPathComponent("com.sabesh.menugram/tdlib-files", isDirectory: true)
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        return filesDir.path
    }

    // MARK: - UI
    static let popoverWidth: CGFloat = 380
    static let popoverHeight: CGFloat = 520
}
