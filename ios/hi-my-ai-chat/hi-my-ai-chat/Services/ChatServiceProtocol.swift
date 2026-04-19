import Foundation

protocol ChatServiceProtocol: Sendable {
    func streamReply(
        for conversation: [OpenAIChatTurn],
        timeoutInterval: TimeInterval,
        maxRetryCount: Int,
        onRetry: (@Sendable (Int) async -> Void)?,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String
}
