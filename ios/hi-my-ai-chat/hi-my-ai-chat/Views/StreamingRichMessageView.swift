import SwiftUI

struct StreamingRichMessageView: View {
    let text: String
    let toolCalls: [ChatToolCall]
    let foreground: Color

    private var blocks: [ChatMessageRenderBlock] {
        ChatMessageContentParser.parse(text: text, toolCalls: toolCalls)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block {
                case .toolCall(let toolCall):
                    ToolCallCardView(toolCall: toolCall)
                case .markdown(let markdown):
                    MarkdownTextBlockView(
                        markdownText: markdown.text,
                        foreground: foreground
                    )
                case .code(let code):
                    CodeFenceBlockView(codeBlock: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("assistant_streaming_rich_content")
    }
}

private struct MarkdownTextBlockView: View {
    private enum Element: Identifiable {
        case heading(id: String, level: Int, text: String)
        case bullet(id: String, text: String)
        case quote(id: String, text: String)
        case paragraph(id: String, text: String)

        var id: String {
            switch self {
            case .heading(let id, _, _),
                 .bullet(let id, _),
                 .quote(let id, _),
                 .paragraph(let id, _):
                return id
            }
        }
    }

    let markdownText: String
    let foreground: Color

    private var elements: [Element] {
        var parsed: [Element] = []
        var paragraphBuffer: [String] = []
        var index = 0

        func nextID(prefix: String) -> String {
            index += 1
            return "\(prefix)-\(index)"
        }

        func flushParagraph() {
            let paragraph = paragraphBuffer
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard paragraph.isEmpty == false else {
                paragraphBuffer.removeAll(keepingCapacity: true)
                return
            }

            parsed.append(.paragraph(id: nextID(prefix: "paragraph"), text: paragraph))
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        for line in markdownText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                parsed.append(
                    .heading(
                        id: nextID(prefix: "heading"),
                        level: heading.level,
                        text: heading.text
                    )
                )
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                parsed.append(
                    .bullet(
                        id: nextID(prefix: "bullet"),
                        text: String(trimmed.dropFirst(2))
                    )
                )
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                parsed.append(
                    .quote(
                        id: nextID(prefix: "quote"),
                        text: String(trimmed.dropFirst(2))
                    )
                )
                continue
            }

            paragraphBuffer.append(trimmed)
        }

        flushParagraph()
        return parsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(elements) { element in
                switch element {
                case .heading(_, let level, let text):
                    InlineMarkdownText(text: text)
                        .font(headingFont(level: level))
                        .fontWeight(.bold)
                case .bullet(_, let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 18, weight: .bold))
                        InlineMarkdownText(text: text)
                    }
                case .quote(_, let text):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(foreground.opacity(0.18))
                            .frame(width: 4)

                        InlineMarkdownText(text: text)
                            .italic()
                    }
                case .paragraph(_, let text):
                    InlineMarkdownText(text: text)
                }
            }
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(foreground)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("markdown_stream_block")
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }

        let content = line.dropFirst(level).trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else { return nil }
        return (level, content)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 27, weight: .bold)
        case 2:
            return .system(size: 24, weight: .bold)
        default:
            return .system(size: 21, weight: .bold)
        }
    }
}

private struct InlineMarkdownText: View {
    let text: String

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
    }
}

private struct CodeFenceBlockView: View {
    let codeBlock: ChatMessageRenderBlock.CodeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(codeBlock.language?.isEmpty == false ? codeBlock.language!.uppercased() : "CODE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.14)))

                Spacer(minLength: 0)

                Text(codeBlock.isComplete ? "已完成" : "流式中")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(codeBlock.isComplete ? Color.green.opacity(0.92) : Color.orange.opacity(0.96))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code.isEmpty ? " " : codeBlock.code)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.13, blue: 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("streaming_code_block")
    }
}

private struct ToolCallCardView: View {
    let toolCall: ChatToolCall

    private var statusLabel: String {
        switch toolCall.status {
        case .running:
            return "调用中"
        case .succeeded:
            return "已完成"
        case .failed:
            return "失败"
        }
    }

    private var statusColor: Color {
        switch toolCall.status {
        case .running:
            return Color.orange
        case .succeeded:
            return Color.green
        case .failed:
            return Color.red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                        .frame(width: 32, height: 32)

                    Image(systemName: "wrench.adjustable")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: toolCall.name))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 0)
            }

            ToolCallPayloadSectionView(
                title: "参数",
                value: prettyPrinted(text: toolCall.argumentsJSON)
            )

            if let output = toolCall.output?.trimmingCharacters(in: .whitespacesAndNewlines),
               output.isEmpty == false {
                ToolCallPayloadSectionView(
                    title: "结果",
                    value: prettyPrinted(text: output)
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusColor.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier("tool_call_card_\(sanitized(toolCall.name))")
    }

    private func displayName(for name: String) -> String {
        switch name {
        case "get_current_datetime":
            return "当前时间"
        case "get_current_location":
            return "当前位置"
        case "get_current_weather":
            return "实时天气"
        case "get_weather_forecast":
            return "天气预报"
        default:
            return name
        }
    }

    private func prettyPrinted(text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let prettyText = String(data: prettyData, encoding: .utf8) else {
            return text
        }

        return prettyText
    }

    private func sanitized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

private struct ToolCallPayloadSectionView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.76))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}
