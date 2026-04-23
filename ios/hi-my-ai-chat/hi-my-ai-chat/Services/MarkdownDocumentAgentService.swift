import Foundation

enum MarkdownDocumentAgentServiceError: LocalizedError, Sendable {
    case missingAPIKey
    case missingBaseURL
    case missingModel
    case invalidBaseURL
    case invalidResponse
    case emptyReply
    case invalidProposal
    case timeout(TimeInterval)
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在设置中填写 OpenAI API Key"
        case .missingBaseURL:
            return "请先在设置中填写 Base URL"
        case .missingModel:
            return "请先在设置中填写 Model"
        case .invalidBaseURL:
            return "Base URL 无效"
        case .invalidResponse:
            return "Markdown agent 响应格式无效"
        case .emptyReply:
            return "Markdown agent 没有返回内容"
        case .invalidProposal:
            return "Markdown agent 没有返回可用提案"
        case .timeout:
            return "Markdown agent 请求超时，请稍后重试"
        case .serverError(_, let message):
            return message
        }
    }
}

struct MarkdownDocumentAgentService: Sendable {
    private struct RequestBody: Encodable, Sendable {
        let model: String
        let messages: [RequestMessage]
        let temperature: Double
        let stream: Bool
    }

    private struct RequestMessage: Encodable, Sendable {
        let role: String
        let content: String
    }

    private struct ResponseBody: Decodable, Sendable {
        struct Choice: Decodable, Sendable {
            struct Message: Decodable, Sendable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct ErrorBody: Decodable, Sendable {
        struct APIError: Decodable, Sendable {
            let message: String?
        }

        let error: APIError?
        let message: String?
    }

    private struct ProposalEnvelope: Decodable, Sendable {
        let summary: String
        let scopeLabel: String
        let updatedMarkdown: String

        private enum CodingKeys: String, CodingKey {
            case summary
            case scopeLabel
            case updatedMarkdown
        }
    }

    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(configuration: OpenAIModelConfiguration? = nil) throws {
        let configuration = configuration ?? OpenAISettings.load()
        let trimmedBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedKey.isEmpty == false else {
            throw MarkdownDocumentAgentServiceError.missingAPIKey
        }

        guard trimmedBaseURL.isEmpty == false else {
            throw MarkdownDocumentAgentServiceError.missingBaseURL
        }

        guard trimmedModel.isEmpty == false else {
            throw MarkdownDocumentAgentServiceError.missingModel
        }

        guard let parsedBaseURL = URL(string: trimmedBaseURL),
              parsedBaseURL.scheme?.isEmpty == false,
              parsedBaseURL.host?.isEmpty == false else {
            throw MarkdownDocumentAgentServiceError.invalidBaseURL
        }

        self.baseURL = parsedBaseURL
        self.apiKey = trimmedKey
        self.model = trimmedModel

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.jsonDecoder = decoder
        self.jsonEncoder = JSONEncoder()
    }

    func proposeEdit(
        fileName: String,
        content: String,
        instruction: String,
        scope: MarkdownAgentEditScope,
        timeoutInterval: TimeInterval = 90
    ) async throws -> MarkdownAgentProposal {
        let request = try makeRequest(
            fileName: fileName,
            content: content,
            instruction: instruction,
            scope: scope,
            timeoutInterval: timeoutInterval
        )

        let startedAt = Date()
        AppLog.markdownAgent("request_start file=\(fileName) scope=\(scope.label)")

        let session = makeURLSession(timeoutInterval: timeoutInterval)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MarkdownDocumentAgentServiceError.invalidResponse
            }

            guard 200 ..< 300 ~= httpResponse.statusCode else {
                throw parseServerError(statusCode: httpResponse.statusCode, data: data)
            }

            let decoded = try jsonDecoder.decode(ResponseBody.self, from: data)
            guard let content = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                content.isEmpty == false else {
                throw MarkdownDocumentAgentServiceError.emptyReply
            }

            let proposal = try parseProposal(from: content)
            AppLog.markdownAgent(
                "request_finish file=\(fileName) duration_ms=\(elapsedMilliseconds(since: startedAt)) summary_chars=\(proposal.summary.count) markdown_chars=\(proposal.updatedMarkdown.count)"
            )
            return proposal
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw MarkdownDocumentAgentServiceError.timeout(timeoutInterval)
            }
            throw error
        }
    }

    private func makeRequest(
        fileName: String,
        content: String,
        instruction: String,
        scope: MarkdownAgentEditScope,
        timeoutInterval: TimeInterval
    ) throws -> URLRequest {
        let endpoint = baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let systemPrompt = """
        你是一个 Markdown 协作编辑 agent。
        你会收到一份 Markdown 文档全文、编辑要求和本次修改范围。
        你必须返回一个 JSON 对象，且只能返回 JSON，不要加代码块，不要加解释。

        JSON schema:
        {
          "summary": "一句中文总结，说明这次修改做了什么",
          "scopeLabel": "这次修改实际落在哪个范围，例如 第 12-18 行 或 ## 风险",
          "updatedMarkdown": "修改后的完整 Markdown 全文"
        }

        规则：
        1. updatedMarkdown 必须是完整文档，不是片段，不是 diff。
        2. 保持 Markdown 结构有效，不要破坏标题层级、列表、表格、代码块围栏和链接格式。
        3. 如果是局部修改，尽量把变更限制在目标范围附近，避免无关改动。
        4. 不要丢失原文已有信息，除非用户明确要求删除。
        5. 如果指令涉及润色、补充、重写，请直接完成；如果指令含糊，优先做最小可接受修改。
        6. JSON 中的字符串必须合法转义。
        """

        let userPrompt = """
        文件名：\(fileName)

        编辑指令：
        \(instruction)

        本次修改范围：
        \(scope.label)

        额外约束：
        \(scope.focusInstructions)

        当前文档全文（带行号，仅供定位参考，输出时不要保留行号）：
        \(MarkdownLineLocator.numberedDocument(content))
        """

        let body = RequestBody(
            model: model,
            messages: [
                RequestMessage(role: "system", content: systemPrompt),
                RequestMessage(role: "user", content: userPrompt)
            ],
            temperature: 0.2,
            stream: false
        )

        request.httpBody = try jsonEncoder.encode(body)
        return request
    }

    private func parseProposal(from rawReply: String) throws -> MarkdownAgentProposal {
        let jsonText = try extractJSONObject(from: rawReply)
        guard let data = jsonText.data(using: .utf8) else {
            throw MarkdownDocumentAgentServiceError.invalidProposal
        }

        let envelope = try jsonDecoder.decode(ProposalEnvelope.self, from: data)
        let summary = envelope.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeLabel = envelope.scopeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedMarkdown = envelope.updatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)

        guard summary.isEmpty == false, updatedMarkdown.isEmpty == false else {
            throw MarkdownDocumentAgentServiceError.invalidProposal
        }

        return MarkdownAgentProposal(
            summary: summary,
            scopeLabel: scopeLabel.isEmpty ? "文档全文" : scopeLabel,
            updatedMarkdown: updatedMarkdown
        )
    }

    private func extractJSONObject(from rawReply: String) throws -> String {
        let trimmed = rawReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw MarkdownDocumentAgentServiceError.emptyReply
        }

        let unwrappedReply: String
        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            if lines.count >= 3 {
                unwrappedReply = lines.dropFirst().dropLast().joined(separator: "\n")
            } else {
                unwrappedReply = trimmed
            }
        } else {
            unwrappedReply = trimmed
        }

        var depth = 0
        var startIndex: String.Index?
        var isInsideString = false
        var isEscaped = false

        for index in unwrappedReply.indices {
            let character = unwrappedReply[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isInsideString.toggle()
                continue
            }

            if isInsideString {
                continue
            }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
                continue
            }

            if character == "}" {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(unwrappedReply[startIndex ... index])
                }
            }
        }

        throw MarkdownDocumentAgentServiceError.invalidProposal
    }

    private func parseServerError(statusCode: Int, data: Data) -> MarkdownDocumentAgentServiceError {
        if let apiError = try? jsonDecoder.decode(ErrorBody.self, from: data),
           let message = apiError.error?.message ?? apiError.message,
           message.isEmpty == false {
            return .serverError(statusCode: statusCode, message: message)
        }

        let rawText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = rawText?.isEmpty == false
            ? rawText!
            : "Markdown agent 请求失败，状态码 \(statusCode)"
        return .serverError(statusCode: statusCode, message: message)
    }

    private func makeURLSession(timeoutInterval: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        max(Int(Date().timeIntervalSince(start) * 1_000), 0)
    }
}
