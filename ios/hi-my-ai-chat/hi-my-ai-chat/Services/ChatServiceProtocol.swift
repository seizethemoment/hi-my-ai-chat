import Foundation

protocol ChatServiceProtocol: Sendable {
    func streamReply(
        for conversation: [OpenAIChatTurn],
        timeoutInterval: TimeInterval,
        maxRetryCount: Int,
        onRetry: (@Sendable (Int) async -> Void)?,
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async throws -> String
}
