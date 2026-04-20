import Foundation
import OSLog

enum AppLog {
    private static let chatToolsLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.github.seizethemoment.hi-my-ai-chat",
        category: "chat-tools"
    )

    static func chatTools(_ message: String) {
        chatToolsLogger.notice("\(message, privacy: .public)")

        #if DEBUG
        print("[chat-tools] \(message)")
        #endif
    }
}
