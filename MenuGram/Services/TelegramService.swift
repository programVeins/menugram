import Foundation
import Observation
import TDLibKit
import SwiftUI

// Auth state for UI binding
enum AuthState: Equatable {
    case loading
    case waitingForPhone
    case waitingForCode(codeInfo: String)
    case waitingForPassword(hint: String)
    case ready
    case error(String)
}

@Observable
final class TelegramService {
    // MARK: - Published State
    var authState: AuthState = .loading
    var chats: [ChatItem] = []
    var currentChatMessages: [MessageItem] = []
    var currentChatId: Int64? = nil
    var isLoadingChats: Bool = false
    var isLoadingMessages: Bool = false
    var isLoadingOlderMessages: Bool = false
    var hasOlderMessages: Bool = true
    var errorMessage: String? = nil
    var currentChatAction: ChatAction? = nil

    // MARK: - Private
    private var manager: TDLibClientManager?
    private var client: TDLibClient?
    private(set) var didInitialLoad: Bool = false
    private static let pageSize: Int = 20

    // MARK: - Initialization
    nonisolated init() {}

    func start() {
        guard manager == nil else { return }
        let mgr = TDLibClientManager()
        self.manager = mgr

        let tdClient = mgr.createClient { [weak self] data, client in
            do {
                let update = try client.decoder.decode(Update.self, from: data)
                Task { @MainActor [weak self] in
                    self?.handleUpdate(update)
                }
            } catch {
                // Non-update responses are handled internally by TDLibKit
            }
        }
        self.client = tdClient
    }

    // MARK: - Update Handler
    private func handleUpdate(_ update: Update) {
        switch update {
        case .updateAuthorizationState(let authUpdate):
            handleAuthorizationState(authUpdate.authorizationState)

        case .updateNewMessage(let newMessage):
            handleNewMessage(newMessage.message)

        case .updateMessageContent(let update):
            handleMessageContentUpdate(chatId: update.chatId, messageId: update.messageId, newContent: update.newContent)

        case .updateChatAction(let actionUpdate):
            handleChatActionUpdate(actionUpdate)

        case .updateChatLastMessage(let chatUpdate):
            handleChatLastMessageUpdate(chatId: chatUpdate.chatId, lastMessage: chatUpdate.lastMessage)

        default:
            break
        }
    }

    // MARK: - Authorization State Machine
    private func handleAuthorizationState(_ state: AuthorizationState) {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            Task { await setParameters() }

        case .authorizationStateWaitPhoneNumber:
            authState = .waitingForPhone

        case .authorizationStateWaitCode(let info):
            let codeType = describeCodeType(info.codeInfo.type)
            authState = .waitingForCode(codeInfo: codeType)

        case .authorizationStateWaitPassword(let info):
            authState = .waitingForPassword(hint: info.passwordHint)

        case .authorizationStateReady:
            authState = .ready
            Task { await refreshChatList() }

        case .authorizationStateClosed:
            authState = .loading
            client = nil
            manager = nil

        default:
            break
        }
    }

    // MARK: - TDLib Parameters
    private func setParameters() async {
        guard let client else { return }
        do {
            // Suppress TDLib's verbose C++ logs
            _ = try? await client.setLogVerbosityLevel(newVerbosityLevel: 0)

            try await client.setTdlibParameters(
                apiHash: AppConstants.apiHash,
                apiId: AppConstants.apiId,
                applicationVersion: AppConstants.appVersion,
                databaseDirectory: AppConstants.databaseDirectory,
                databaseEncryptionKey: Data(),
                deviceModel: AppConstants.deviceModel,
                filesDirectory: AppConstants.filesDirectory,
                systemLanguageCode: AppConstants.systemLanguageCode,
                systemVersion: "",
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: false,
                useTestDc: false
            )
        } catch {
            authState = .error("Failed to initialize: \(error.localizedDescription)")
        }
    }

    // MARK: - Auth Actions
    func sendPhoneNumber(_ phone: String) async {
        guard let client else { return }
        do {
            try await client.setAuthenticationPhoneNumber(
                phoneNumber: phone,
                settings: nil
            )
        } catch {
            authState = .error("Invalid phone number: \(error.localizedDescription)")
        }
    }

    func sendAuthCode(_ code: String) async {
        guard let client else { return }
        do {
            try await client.checkAuthenticationCode(code: code)
        } catch {
            authState = .error("Invalid code: \(error.localizedDescription)")
        }
    }

    func sendPassword(_ password: String) async {
        guard let client else { return }
        do {
            try await client.checkAuthenticationPassword(password: password)
        } catch {
            authState = .error("Invalid password: \(error.localizedDescription)")
        }
    }

    // MARK: - Chat List
    func refreshChatList() async {
        guard let client else { return }
        isLoadingChats = true
        defer { isLoadingChats = false }

        do {
            try await client.loadChats(chatList: .chatListMain, limit: 5)

            let searchResult = try await client.searchChats(limit: 1, query: AppConstants.botName)
            if let chatId = searchResult.chatIds.first {
                let chat = try await client.getChat(chatId: chatId)
                var item = ChatItem(from: chat)
                // Download profile photo if available
                if let photoFileId = item.photoFileId {
                    item.photoLocalPath = await downloadPhoto(fileId: photoFileId)
                }
                self.chats = [item]

                if currentChatId == nil {
                    await loadMessages(chatId: chatId)
                }
                return
            }

            // Fallback
            let result = try await client.getChats(chatList: .chatListMain, limit: 5)
            var items: [ChatItem] = []
            for chatId in result.chatIds {
                if let chat = try? await client.getChat(chatId: chatId) {
                    var item = ChatItem(from: chat)
                    if let photoFileId = item.photoFileId {
                        item.photoLocalPath = await downloadPhoto(fileId: photoFileId)
                    }
                    items.append(item)
                }
            }
            self.chats = items

            if currentChatId == nil,
               let bot = items.first(where: { $0.title.localizedCaseInsensitiveContains(AppConstants.botName) }) {
                await loadMessages(chatId: bot.id)
            }
        } catch {
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
        }
    }

    // MARK: - Messages
    func loadMessages(chatId: Int64) async {
        guard let client else { return }
        self.currentChatId = chatId
        self.currentChatMessages = []
        self.currentChatAction = nil
        self.hasOlderMessages = true
        self.didInitialLoad = false
        isLoadingMessages = true
        defer { isLoadingMessages = false }

        do {
            // First attempt — TDLib may return only cached messages
            var fetched = try await fetchHistory(
                client: client, chatId: chatId,
                fromMessageId: 0, limit: Self.pageSize
            )

            // If TDLib returned very few messages, retry after a short delay
            // to allow the server sync to complete
            if fetched.count < 5 {
                try? await Task.sleep(for: .milliseconds(500))
                let retry = try await fetchHistory(
                    client: client, chatId: chatId,
                    fromMessageId: 0, limit: Self.pageSize
                )
                if retry.count > fetched.count {
                    fetched = retry
                }
            }

            let messages = fetched.map { MessageItem(from: $0) }
            self.currentChatMessages = messages.reversed()
            self.hasOlderMessages = true
            self.didInitialLoad = true

            if let lastMessageId = fetched.first?.id {
                _ = try? await client.viewMessages(
                    chatId: chatId,
                    forceRead: true,
                    messageIds: [lastMessageId],
                    source: nil
                )
            }
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    private func fetchHistory(
        client: TDLibClient, chatId: Int64,
        fromMessageId: Int64, limit: Int
    ) async throws -> [Message] {
        let history = try await client.getChatHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            limit: limit,
            offset: 0,
            onlyLocal: false
        )
        return history.messages ?? []
    }

    func loadOlderMessages() async {
        guard let client,
              let chatId = currentChatId,
              didInitialLoad,
              !isLoadingOlderMessages,
              hasOlderMessages,
              let oldestMessage = currentChatMessages.first else { return }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        do {
            let history = try await client.getChatHistory(
                chatId: chatId,
                fromMessageId: oldestMessage.id,
                limit: Self.pageSize,
                offset: 0,
                onlyLocal: false
            )

            let fetched = history.messages ?? []
            if fetched.isEmpty {
                self.hasOlderMessages = false
                return
            }

            let olderMessages = fetched.map { MessageItem(from: $0) }
            // Only stop pagination when server returns nothing
            self.hasOlderMessages = !fetched.isEmpty
            self.currentChatMessages.insert(contentsOf: olderMessages.reversed(), at: 0)
        } catch {
            errorMessage = "Failed to load older messages: \(error.localizedDescription)"
        }
    }

    // MARK: - File Downloads
    func downloadPhoto(fileId: Int) async -> String? {
        guard let client else { return nil }
        do {
            let file = try await client.downloadFile(
                fileId: fileId,
                limit: 0,
                offset: 0,
                priority: 16,
                synchronous: true
            )
            return file.local.isDownloadingCompleted ? file.local.path : nil
        } catch {
            return nil
        }
    }

    func downloadVoiceNote(fileId: Int) async -> String? {
        guard let client else { return nil }
        do {
            let file = try await client.downloadFile(
                fileId: fileId,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true
            )
            return file.local.isDownloadingCompleted ? file.local.path : nil
        } catch {
            return nil
        }
    }

    func sendVoiceNote(chatId: Int64, filePath: String, duration: Int, waveform: Data) async {
        guard let client else { return }
        do {
            let content = InputMessageContent.inputMessageVoiceNote(
                InputMessageVoiceNote(
                    caption: nil,
                    duration: duration,
                    selfDestructType: nil,
                    voiceNote: .inputFileLocal(InputFileLocal(path: filePath)),
                    waveform: waveform
                )
            )
            _ = try await client.sendMessage(
                chatId: chatId,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: nil
            )
        } catch {
            errorMessage = "Failed to send voice note: \(error.localizedDescription)"
        }
    }

    func sendMessage(chatId: Int64, text: String) async {
        guard let client else { return }
        do {
            let content = InputMessageContent.inputMessageText(
                InputMessageText(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: text)
                )
            )
            _ = try await client.sendMessage(
                chatId: chatId,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: nil
            )
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }

    // MARK: - Real-time Updates
    private func handleNewMessage(_ message: Message) {
        let item = MessageItem(from: message)

        if message.chatId == currentChatId {
            withAnimation(.easeIn(duration: 0.3)) {
                currentChatMessages.append(item)
            }
        }

        if let index = chats.firstIndex(where: { $0.id == message.chatId }) {
            chats[index].lastMessagePreview = item.textContent
            chats[index].lastMessageDate = item.date
        }
    }

    private func handleMessageContentUpdate(chatId: Int64, messageId: Int64, newContent: MessageContent) {
        if chatId == currentChatId,
           let index = currentChatMessages.firstIndex(where: { $0.id == messageId }) {
            if case .messageText(let text) = newContent {
                withAnimation(.easeIn(duration: 0.15)) {
                    currentChatMessages[index].textContent = text.text.text
                }
            }
        }
    }

    private func handleChatLastMessageUpdate(chatId: Int64, lastMessage: Message?) {
        guard let lastMessage else { return }
        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            let item = MessageItem(from: lastMessage)
            chats[index].lastMessagePreview = item.textContent
            chats[index].lastMessageDate = item.date
        }
    }

    private func handleChatActionUpdate(_ update: UpdateChatAction) {
        guard update.chatId == currentChatId else { return }
        // Only show actions from the other person, not ourselves
        if case .messageSenderUser = update.senderId {
            withAnimation(.easeInOut(duration: 0.2)) {
                if case .chatActionCancel = update.action {
                    currentChatAction = nil
                } else {
                    currentChatAction = update.action
                }
            }
        }
    }

    // MARK: - Helpers
    private func describeCodeType(_ type: AuthenticationCodeType) -> String {
        switch type {
        case .authenticationCodeTypeTelegramMessage:
            return "Check your Telegram messages"
        case .authenticationCodeTypeSms:
            return "SMS code sent"
        case .authenticationCodeTypeFragment:
            return "Check Fragment"
        default:
            return "Enter the code"
        }
    }

    // MARK: - Cleanup
    func stop() {
        manager?.closeClients()
        manager = nil
        client = nil
    }
}
