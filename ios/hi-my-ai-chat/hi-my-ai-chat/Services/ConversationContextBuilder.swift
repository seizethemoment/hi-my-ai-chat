import Foundation

struct ConversationContextBuilder: Sendable {
    struct Limits: Sendable {
        let minimumRecentMessages: Int
        let maximumRecentMessages: Int
        let recentBudget: Int
        let compressionTriggerBudget: Int
        let maxRetainedImageMessages: Int
        let maxSummaryCharacters: Int
        let maxSummaryItems: Int
        let maxSnippetCharacters: Int

        static let `default` = Limits(
            minimumRecentMessages: 4,
            maximumRecentMessages: 8,
            recentBudget: 4_800,
            compressionTriggerBudget: 6_500,
            maxRetainedImageMessages: 2,
            maxSummaryCharacters: 1_400,
            maxSummaryItems: 12,
            maxSnippetCharacters: 180
        )
    }

    private let limits: Limits

    init(limits: Limits = .default) {
        self.limits = limits
    }

    func makeTurns(from messages: [ChatMessage]) -> [OpenAIChatTurn] {
        guard messages.isEmpty == false else { return [] }

        let summarizedPrefixCount = summarizedPrefixCount(in: messages)
        let earlierMessages = Array(messages.prefix(summarizedPrefixCount))
        let recentMessages = Array(messages.dropFirst(summarizedPrefixCount))
        let preparedRecentMessages = prepareRecentMessages(recentMessages)

        var turns: [OpenAIChatTurn] = []
        if let summary = makeSummary(from: earlierMessages) {
            turns.append(
                OpenAIChatTurn(
                    role: .system,
                    text: summary,
                    imageDataURLs: []
                )
            )
        }

        turns.append(contentsOf: preparedRecentMessages.map(makeTurn))
        return turns
    }

    private func summarizedPrefixCount(in messages: [ChatMessage]) -> Int {
        let totalBudget = messages.reduce(into: 0) { partialResult, message in
            partialResult += estimatedUnits(for: message)
        }
        let totalImageMessages = messages.reduce(into: 0) { partialResult, message in
            if message.attachments.isEmpty == false {
                partialResult += 1
            }
        }
        let shouldCompress =
            totalBudget > limits.compressionTriggerBudget
            || messages.count > limits.maximumRecentMessages
            || totalImageMessages > limits.maxRetainedImageMessages

        guard shouldCompress else { return 0 }

        var keptCount = 0
        var keptBudget = 0

        for message in messages.reversed() {
            let nextCount = keptCount + 1
            let nextBudget = keptBudget + estimatedUnits(for: message)
            let mustKeep = keptCount < limits.minimumRecentMessages
            let fitsBudget = nextCount <= limits.maximumRecentMessages && nextBudget <= limits.recentBudget

            if mustKeep || fitsBudget {
                keptCount = nextCount
                keptBudget = nextBudget
            } else {
                break
            }
        }

        return max(messages.count - keptCount, 0)
    }

    private func prepareRecentMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard messages.isEmpty == false else { return [] }

        var preparedMessages = messages
        var remainingImageSlots = limits.maxRetainedImageMessages

        for index in preparedMessages.indices.reversed() {
            guard preparedMessages[index].attachments.isEmpty == false else { continue }

            if remainingImageSlots > 0 {
                remainingImageSlots -= 1
                continue
            }

            let removedImageCount = preparedMessages[index].attachments.count
            preparedMessages[index].attachments = []
            preparedMessages[index].text = mergedMessageText(
                preparedMessages[index].text,
                note: "本条消息原含 \(removedImageCount) 张图片，旧图片内容已从上下文中裁剪。"
            )
        }

        return preparedMessages
    }

    private func makeSummary(from messages: [ChatMessage]) -> String? {
        guard messages.isEmpty == false else { return nil }

        var lines = [
            "以下是更早对话的压缩摘要，请延续其中已经确认的事实、偏好和未完成问题；如果与用户最新消息冲突，以最新消息为准。"
        ]
        var usedCharacters = lines[0].count
        var appendedItems = 0

        for message in messages {
            guard appendedItems < limits.maxSummaryItems else { break }

            let snippet = summarySnippet(for: message)
            guard snippet.isEmpty == false else { continue }

            let line = "- \(message.role.contextSummaryLabel)：\(snippet)"
            if usedCharacters + line.count + 1 > limits.maxSummaryCharacters {
                break
            }

            lines.append(line)
            usedCharacters += line.count + 1
            appendedItems += 1
        }

        guard lines.count > 1 else { return nil }
        if appendedItems < messages.count {
            let omittedLine = "- 更早还有一些细节已省略。"
            if usedCharacters + omittedLine.count + 1 <= limits.maxSummaryCharacters {
                lines.append(omittedLine)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func summarySnippet(for message: ChatMessage) -> String {
        var components: [String] = []
        let normalizedText = normalizedText(message.text)

        if normalizedText.isEmpty == false {
            components.append(truncated(normalizedText, limit: limits.maxSnippetCharacters))
        }

        if message.attachments.isEmpty == false {
            components.append("附带 \(message.attachments.count) 张图片")
        }

        return components.joined(separator: "；")
    }

    private func makeTurn(from message: ChatMessage) -> OpenAIChatTurn {
        OpenAIChatTurn(
            role: message.role.openAIChatRole,
            text: message.text,
            imageDataURLs: message.attachments.map(\.dataURL)
        )
    }

    private func estimatedUnits(for message: ChatMessage) -> Int {
        let textUnits = normalizedText(message.text).count
        let imageUnits = message.attachments.count * 1_800
        return max(textUnits + imageUnits, 1)
    }

    private func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    private func mergedMessageText(_ text: String, note: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else { return note }
        return "\(trimmedText)\n\n[\(note)]"
    }
}

private extension ChatMessage.Role {
    var openAIChatRole: OpenAIChatRole {
        switch self {
        case .user:
            return .user
        case .assistant:
            return .assistant
        }
    }

    var contextSummaryLabel: String {
        switch self {
        case .user:
            return "用户"
        case .assistant:
            return "助手"
        }
    }
}
