import Foundation
import OSLog

enum AppLog {
    private static let chatToolsLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.github.seizethemoment.hi-my-ai-chat",
        category: "chat-tools"
    )
    private static let markdownAgentLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.github.seizethemoment.hi-my-ai-chat",
        category: "markdown-agent"
    )

    static func chatTools(_ message: String) {
        chatToolsLogger.notice("\(message, privacy: .public)")

        #if DEBUG
        print("[chat-tools] \(message)")
        #endif
    }

    static func markdownAgent(_ message: String) {
        markdownAgentLogger.notice("\(message, privacy: .public)")

        #if DEBUG
        print("[markdown-agent] \(message)")
        #endif
    }
}
