import Combine
import Foundation

struct ChatSession: Identifiable, Equatable {
    static let defaultTitle = "新聊天"

    let id: UUID
    var customTitle: String?
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    var title: String {
        Self.resolvedTitle(for: messages, customTitle: customTitle)
    }

    var previewText: String {
        for message in messages.reversed() {
            let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty == false {
                return trimmedText
            }

            if let firstDocument = message.documentAttachments.first {
                return "[文件] \(firstDocument.fileName)"
            }

            if message.attachments.isEmpty == false {
                return message.attachments.count == 1 ? "[图片]" : "[\(message.attachments.count) 张图片]"
            }
        }

        return "还没有消息"
    }

    static func normalizedCustomTitle(_ title: String?) -> String? {
        guard let title else { return nil }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    static func resolvedTitle(for messages: [ChatMessage], customTitle: String?) -> String {
        if let customTitle = normalizedCustomTitle(customTitle) {
            return customTitle
        }

        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            return defaultTitle
        }

        let trimmedText = firstUserMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            if firstUserMessage.documentAttachments.isEmpty == false {
                return "文档提问"
            }

            return firstUserMessage.attachments.isEmpty ? defaultTitle : "图片提问"
        }

        let compactText = trimmedText.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let prefix = String(compactText.prefix(7))
        return prefix.isEmpty ? defaultTitle : prefix
    }
}

@MainActor
final class ChatSessionStore: ObservableObject {
    @Published private(set) var sessions: [ChatSession] = []
    @Published private(set) var selectedSessionID: UUID?

    private let saveURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(saveURL: URL? = nil) {
        self.saveURL = saveURL ?? Self.defaultSaveURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        load()
        ensureSessionExists()
    }

    var selectedSession: ChatSession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    func session(for id: UUID) -> ChatSession? {
        sessions.first(where: { $0.id == id })
    }

    @discardableResult
    func selectSession(id: UUID) -> ChatSession? {
        guard let session = session(for: id) else { return nil }
        selectedSessionID = session.id
        save()
        return session
    }

    @discardableResult
    func createSession(select: Bool = true) -> ChatSession {
        let session = ChatSession(
            id: UUID(),
            customTitle: nil,
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )

        sessions.insert(session, at: 0)
        if select {
            selectedSessionID = session.id
        }
        save()
        return session
    }

    func updateMessages(_ messages: [ChatMessage], for sessionID: UUID, shouldRefreshTimestamp: Bool = true) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        sessions[index].messages = messages
        if shouldRefreshTimestamp {
            sessions[index].updatedAt = messages.isEmpty ? sessions[index].createdAt : Date()
        }
        sessions = sortedSessions(sessions)
        save()
    }

    func renameSession(id: UUID, customTitle: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        sessions[index].customTitle = ChatSession.normalizedCustomTitle(customTitle)
        save()
    }

    @discardableResult
    func deleteSession(id: UUID) -> ChatSession? {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return selectedSession }

        sessions.remove(at: index)

        if sessions.isEmpty {
            let session = createSession(select: true)
            selectedSessionID = session.id
            return session
        }

        if selectedSessionID == id {
            selectedSessionID = sortedSessions(sessions).first?.id
        }

        sessions = sortedSessions(sessions)
        save()
        return selectedSession
    }

    func filteredSessions(matching query: String) -> [ChatSession] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allSessions = sortedSessions(sessions)

        guard normalizedQuery.isEmpty == false else {
            return allSessions
        }

        return allSessions.filter { session in
            session.title.localizedCaseInsensitiveContains(normalizedQuery)
                || session.previewText.localizedCaseInsensitiveContains(normalizedQuery)
                || session.messages.contains(where: { message in
                    message.text.localizedCaseInsensitiveContains(normalizedQuery)
                })
        }
    }

    func reusableEmptySession() -> ChatSession? {
        sortedSessions(sessions).first { session in
            session.messages.isEmpty
        }
    }

    private func ensureSessionExists() {
        if sessions.isEmpty {
            let session = createSession(select: true)
            selectedSessionID = session.id
            return
        }

        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) {
            sessions = sortedSessions(sessions)
            return
        }

        sessions = sortedSessions(sessions)
        selectedSessionID = sessions.first?.id
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else {
            return
        }

        do {
            let persistedState = try decoder.decode(PersistedChatSessionState.self, from: data)
            selectedSessionID = persistedState.selectedSessionID
            sessions = persistedState.sessions.map(\.chatSession)
        } catch {
            sessions = []
            selectedSessionID = nil
        }
    }

    private func save() {
        let persistedState = PersistedChatSessionState(
            selectedSessionID: selectedSessionID,
            sessions: sessions.map(PersistedChatSession.init)
        )

        do {
            let data = try encoder.encode(persistedState)
            let directory = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: saveURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save chat sessions: \(error)")
        }
    }

    private func sortedSessions(_ sessions: [ChatSession]) -> [ChatSession] {
        sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static var defaultSaveURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documentsDirectory.appendingPathComponent("chat_sessions.json")
    }
}

private struct PersistedChatSessionState: Codable {
    var selectedSessionID: UUID?
    var sessions: [PersistedChatSession]
}

private struct PersistedChatSession: Codable {
    let id: UUID
    let title: String?
    let customTitle: String?
    let createdAt: Date
    let updatedAt: Date
    let messages: [PersistedChatMessage]

    @MainActor
    init(session: ChatSession) {
        self.id = session.id
        self.title = session.title
        self.customTitle = session.customTitle
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
        self.messages = session.messages.compactMap(PersistedChatMessage.init)
    }

    var chatSession: ChatSession {
        ChatSession(
            id: id,
            customTitle: customTitle,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: messages.map(\.chatMessage)
        )
    }
}

private struct PersistedChatMessage: Codable {
    let id: UUID
    let role: String
    let text: String
    let attachments: [PersistedChatImageAttachment]
    let documentAttachments: [ChatDocumentAttachment]
    let toolCalls: [ChatToolCall]
    let showsActions: Bool
    let state: String
    let favoritedAt: Date?

    @MainActor
    init?(message: ChatMessage) {
        let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.state == .streaming,
           trimmedText.isEmpty,
           message.attachments.isEmpty,
           message.documentAttachments.isEmpty {
            return nil
        }

        self.id = message.id
        self.role = message.role == .user ? "user" : "assistant"
        self.text = message.text
        self.attachments = message.attachments.map(PersistedChatImageAttachment.init)
        self.documentAttachments = message.documentAttachments
        self.toolCalls = message.toolCalls
        self.showsActions = message.role == .assistant && trimmedText.isEmpty == false
        self.state = message.state == .failed ? "failed" : "complete"
        self.favoritedAt = message.favoritedAt
    }

    var chatMessage: ChatMessage {
        ChatMessage(
            id: id,
            role: role == "user" ? .user : .assistant,
            text: text,
            attachments: attachments.map(\.attachment),
            documentAttachments: documentAttachments,
            toolCalls: toolCalls,
            showsActions: showsActions,
            state: state == "failed" ? .failed : .complete,
            favoritedAt: favoritedAt
        )
    }
}

private struct PersistedChatImageAttachment: Codable {
    let id: UUID
    let data: Data
    let mimeType: String

    init(attachment: ChatImageAttachment) {
        self.id = attachment.id
        self.data = attachment.data
        self.mimeType = attachment.mimeType
    }

    var attachment: ChatImageAttachment {
        ChatImageAttachment(id: id, data: data, mimeType: mimeType)
    }
}
