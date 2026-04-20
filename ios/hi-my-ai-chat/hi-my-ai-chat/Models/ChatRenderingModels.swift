import Foundation

struct ChatToolCall: Identifiable, Equatable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case running
        case succeeded
        case failed
    }

    let id: String
    let name: String
    var argumentsJSON: String
    var output: String?
    var status: Status
}

enum ChatStreamEvent: Sendable {
    case textDelta(String)
    case toolCall(ChatToolCall)
}

enum ChatMessageRenderBlock: Equatable, Identifiable {
    struct MarkdownBlock: Equatable {
        let id: String
        let text: String
    }

    struct CodeBlock: Equatable {
        let id: String
        let language: String?
        let code: String
        let isComplete: Bool
    }

    case toolCall(ChatToolCall)
    case markdown(MarkdownBlock)
    case code(CodeBlock)

    var id: String {
        switch self {
        case .toolCall(let toolCall):
            return "tool-\(toolCall.id)"
        case .markdown(let block):
            return block.id
        case .code(let block):
            return block.id
        }
    }
}

struct ChatMessageContentParser {
    static func parse(text: String, toolCalls: [ChatToolCall]) -> [ChatMessageRenderBlock] {
        var blocks = toolCalls.map(ChatMessageRenderBlock.toolCall)
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalizedText.isEmpty == false else {
            return blocks
        }

        var markdownBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var isInsideCodeBlock = false
        var markdownIndex = 0
        var codeIndex = 0

        func flushMarkdown() {
            let joined = markdownBuffer.joined(separator: "\n")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                markdownBuffer.removeAll(keepingCapacity: true)
                return
            }

            markdownIndex += 1
            blocks.append(
                .markdown(
                    .init(
                        id: "markdown-\(markdownIndex)",
                        text: joined
                    )
                )
            )
            markdownBuffer.removeAll(keepingCapacity: true)
        }

        func flushCode(isComplete: Bool) {
            codeIndex += 1
            blocks.append(
                .code(
                    .init(
                        id: "code-\(codeIndex)",
                        language: codeLanguage,
                        code: codeBuffer.joined(separator: "\n"),
                        isComplete: isComplete
                    )
                )
            )
            codeBuffer.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        for line in normalizedText.components(separatedBy: "\n") {
            if isInsideCodeBlock {
                if line.hasPrefix("```") {
                    flushCode(isComplete: true)
                    isInsideCodeBlock = false
                } else {
                    codeBuffer.append(line)
                }
                continue
            }

            if line.hasPrefix("```") {
                flushMarkdown()
                isInsideCodeBlock = true

                let language = line
                    .dropFirst(3)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                codeLanguage = language.isEmpty ? nil : language
                continue
            }

            markdownBuffer.append(line)
        }

        if isInsideCodeBlock {
            flushCode(isComplete: false)
        } else {
            flushMarkdown()
        }

        return blocks
    }
}

enum ChatDemoScenario: String, Sendable {
    case richStreaming
    case toolFailure
}
