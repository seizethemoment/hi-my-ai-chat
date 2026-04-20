import Foundation

enum OpenAIChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct OpenAIChatTurn: Sendable {
    let role: OpenAIChatRole
    let text: String
    let imageDataURLs: [String]
}

enum OpenAIChatServiceError: LocalizedError, Sendable {
    case missingAPIKey
    case missingBaseURL
    case missingModel
    case invalidBaseURL
    case invalidResponse
    case emptyReply
    case timeout(TimeInterval)
    case serverError(statusCode: Int, message: String)
    case tooManyToolRounds

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
            return "OpenAI 兼容服务响应格式无效"
        case .emptyReply:
            return "模型没有返回内容"
        case .timeout:
            return "请求超时，请稍后重试"
        case .serverError(_, let message):
            return message
        case .tooManyToolRounds:
            return "工具调用轮次过多，请换个问法重试"
        }
    }
}

struct OpenAIChatService: ChatServiceProtocol, Sendable {
    private struct RequestBody: Encodable, Sendable {
        let model: String
        let messages: [RequestMessage]
        let temperature: Double
        let stream: Bool
        let tools: [OpenAIChatToolDefinition]
        let toolChoice: String
        let parallelToolCalls: Bool

        private enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case stream
            case tools
            case toolChoice = "tool_choice"
            case parallelToolCalls = "parallel_tool_calls"
        }
    }

    private struct RequestMessage: Encodable, Sendable {
        enum Content: Encodable, Sendable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var singleValueContainer = encoder.singleValueContainer()

                switch self {
                case .text(let text):
                    try singleValueContainer.encode(text)
                case .parts(let parts):
                    try singleValueContainer.encode(parts)
                }
            }
        }

        struct ContentPart: Encodable, Sendable {
            struct ImageURLPayload: Encodable, Sendable {
                let url: String
                let detail: String
            }

            let type: String
            let text: String?
            let imageURL: ImageURLPayload?

            private enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            static func text(_ value: String) -> ContentPart {
                ContentPart(type: "text", text: value, imageURL: nil)
            }

            static func image(url: String) -> ContentPart {
                ContentPart(
                    type: "image_url",
                    text: nil,
                    imageURL: ImageURLPayload(url: url, detail: "auto")
                )
            }
        }

        let role: OpenAIChatRole
        let content: Content?
        let toolCallID: String?
        let toolCalls: [ToolCall]?

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCallID = "tool_call_id"
            case toolCalls = "tool_calls"
        }
    }

    private struct ToolCall: Codable, Sendable {
        struct Function: Codable, Sendable {
            let name: String
            let arguments: String
        }

        let id: String
        let type: String
        let function: Function
    }

    private struct ResponseBody: Decodable, Sendable {
        struct Choice: Decodable, Sendable {
            struct Message: Decodable, Sendable {
                let role: OpenAIChatRole
                let content: String?
                let toolCalls: [ToolCall]?
            }

            let message: Message
            let finishReason: String?
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

    private static let maxToolCallRounds = 6
    private static let toolSystemPrompt = """
    你可以使用以下真实工具能力：当前日期时间、当前地理位置、实时天气、未来天气预报。
    凡是涉及今天几月几号、今天星期几、现在几点、当前时间、当前日期、时区、当前位置、我在哪里、附近去哪里玩、实时天气、当前温度、是否下雨、明天或未来几天的天气预报等问题，都必须优先调用相应工具，不要凭记忆回答。
    如果用户询问明天、后天、周末、下周或未来几天的天气、温度、降雨、是否适合出门，要优先使用天气预报工具。
    如果用户询问去哪里玩、附近玩什么、周边有什么适合逛的地方，而答案依赖用户当前所在地，要优先使用定位工具；如果还涉及明天或未来天气，再结合天气预报工具。
    如果工具返回失败信息，要基于失败原因直接告诉用户，例如定位权限未开启或天气服务暂时不可用。
    """

    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let toolExecutor: BuiltinChatToolExecutor

    init(
        configuration: OpenAIModelConfiguration? = nil,
        systemPrompt: String = OpenAISettings.systemPrompt,
        toolExecutor: BuiltinChatToolExecutor = BuiltinChatToolExecutor()
    ) throws {
        let configuration = configuration ?? OpenAISettings.load()
        let trimmedBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedKey.isEmpty == false else {
            throw OpenAIChatServiceError.missingAPIKey
        }

        guard trimmedBaseURL.isEmpty == false else {
            throw OpenAIChatServiceError.missingBaseURL
        }

        guard trimmedModel.isEmpty == false else {
            throw OpenAIChatServiceError.missingModel
        }

        guard let parsedBaseURL = URL(string: trimmedBaseURL),
              parsedBaseURL.scheme?.isEmpty == false,
              parsedBaseURL.host?.isEmpty == false else {
            throw OpenAIChatServiceError.invalidBaseURL
        }

        self.baseURL = parsedBaseURL
        self.apiKey = trimmedKey
        self.model = trimmedModel
        self.systemPrompt = systemPrompt
        self.toolExecutor = toolExecutor

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.jsonDecoder = decoder

        self.jsonEncoder = JSONEncoder()
    }

    func streamReply(
        for conversation: [OpenAIChatTurn],
        timeoutInterval: TimeInterval = 45,
        maxRetryCount: Int = 1,
        onRetry: (@Sendable (Int) async -> Void)? = nil,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let requestMessages = makeRequestMessages(for: conversation)

        for attempt in 0...maxRetryCount {
            do {
                let reply = try await completeReply(
                    messages: requestMessages,
                    timeoutInterval: timeoutInterval
                )
                await onDelta(reply)
                return reply
            } catch {
                let shouldRetry = attempt < maxRetryCount && shouldRetry(after: error)
                guard shouldRetry else {
                    throw error
                }

                await onRetry?(attempt + 1)
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }

        throw OpenAIChatServiceError.invalidResponse
    }

    private func completeReply(
        messages initialMessages: [RequestMessage],
        timeoutInterval: TimeInterval
    ) async throws -> String {
        var messages = initialMessages
        let session = makeURLSession(timeoutInterval: timeoutInterval)
        defer { session.invalidateAndCancel() }

        for round in 1...Self.maxToolCallRounds {
            try Task.checkCancellation()

            let requestID = UUID().uuidString
            let request = try makeRequest(
                messages: messages,
                timeoutInterval: timeoutInterval,
                requestID: requestID
            )

            AppLog.chatTools("round=\(round) client_request_id=\(requestID) message_count=\(messages.count)")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIChatServiceError.invalidResponse
            }

            AppLog.chatTools(
                "round=\(round) status=\(httpResponse.statusCode) x_request_id=\(httpResponse.value(forHTTPHeaderField: "x-request-id") ?? "-")"
            )

            guard 200 ..< 300 ~= httpResponse.statusCode else {
                throw parseServerError(statusCode: httpResponse.statusCode, data: data)
            }

            let decoded = try jsonDecoder.decode(ResponseBody.self, from: data)
            guard let choice = decoded.choices.first else {
                throw OpenAIChatServiceError.invalidResponse
            }

            let toolCalls = choice.message.toolCalls ?? []
            let trimmedContent = choice.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let toolNames = toolCalls.map(\.function.name).joined(separator: ",")

            AppLog.chatTools(
                "round=\(round) finish_reason=\(choice.finishReason ?? "-") tool_calls=\(toolCalls.count) tool_names=\(toolNames.isEmpty ? "-" : toolNames) content_chars=\(trimmedContent?.count ?? 0)"
            )

            if toolCalls.isEmpty {
                guard let reply = trimmedContent, reply.isEmpty == false else {
                    throw OpenAIChatServiceError.emptyReply
                }

                AppLog.chatTools("final_reply_chars=\(reply.count)")
                return reply
            }

            messages.append(
                RequestMessage(
                    role: .assistant,
                    content: choice.message.content.map(RequestMessage.Content.text),
                    toolCallID: nil,
                    toolCalls: toolCalls
                )
            )

            for toolCall in toolCalls {
                AppLog.chatTools(
                    "tool_call round=\(round) id=\(toolCall.id) name=\(toolCall.function.name) arguments=\(toolCall.function.arguments)"
                )

                let toolOutput = await toolExecutor.execute(
                    named: toolCall.function.name,
                    argumentsJSON: toolCall.function.arguments
                )
                let truncatedOutput = truncateForLog(toolOutput)

                AppLog.chatTools(
                    "tool_output round=\(round) id=\(toolCall.id) name=\(toolCall.function.name) output=\(truncatedOutput)"
                )

                messages.append(
                    RequestMessage(
                        role: .tool,
                        content: .text(toolOutput),
                        toolCallID: toolCall.id,
                        toolCalls: nil
                    )
                )
            }
        }

        throw OpenAIChatServiceError.tooManyToolRounds
    }

    private func makeRequest(
        messages: [RequestMessage],
        timeoutInterval: TimeInterval,
        requestID: String
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
        request.setValue(requestID, forHTTPHeaderField: "X-Client-Request-Id")

        let body = RequestBody(
            model: model,
            messages: messages,
            temperature: 0.7,
            stream: false,
            tools: toolExecutor.toolDefinitions,
            toolChoice: "auto",
            parallelToolCalls: false
        )

        request.httpBody = try jsonEncoder.encode(body)
        return request
    }

    private func makeRequestMessages(for conversation: [OpenAIChatTurn]) -> [RequestMessage] {
        let supplementalSystemPrompts = conversation
            .filter { $0.role == .system }
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let mergedSystemPrompt = (
            [systemPrompt, Self.toolSystemPrompt]
            + supplementalSystemPrompts
            + toolPriorityPrompts(for: conversation)
        )
            .joined(separator: "\n\n")

        return [RequestMessage(role: .system, content: .text(mergedSystemPrompt), toolCallID: nil, toolCalls: nil)]
            + conversation
                .filter { $0.role != .system }
                .map(makeRequestMessage(for:))
    }

    private func makeRequestMessage(for turn: OpenAIChatTurn) -> RequestMessage {
        guard turn.imageDataURLs.isEmpty == false else {
            return RequestMessage(
                role: turn.role,
                content: .text(turn.text),
                toolCallID: nil,
                toolCalls: nil
            )
        }

        let textParts = turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [RequestMessage.ContentPart.text(turn.text)]
        let imageParts = turn.imageDataURLs.map { url in
            RequestMessage.ContentPart.image(url: url)
        }

        return RequestMessage(
            role: turn.role,
            content: .parts(textParts + imageParts),
            toolCallID: nil,
            toolCalls: nil
        )
    }

    private func toolPriorityPrompts(for conversation: [OpenAIChatTurn]) -> [String] {
        guard let latestUserTurn = conversation.last(where: { $0.role == .user }) else {
            return []
        }

        let normalizedText = latestUserTurn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else { return [] }

        var prompts: [String] = []

        if isCurrentDateTimeQuestion(normalizedText) {
            prompts.append("当前这条用户消息依赖实时日期或时间，请优先调用 `get_current_datetime`，不要直接作答。")
        }

        if isCurrentLocationQuestion(normalizedText) {
            prompts.append("当前这条用户消息依赖设备实时位置，请优先调用 `get_current_location`，不要直接作答。")
        }

        if isForecastWeatherQuestion(normalizedText) {
            prompts.append("当前这条用户消息依赖未来天气预报，请优先调用 `get_weather_forecast`；如果用户没有给出地点，优先判断是否需要当前位置。")
        }

        if isWeatherQuestion(normalizedText), isForecastWeatherQuestion(normalizedText) == false {
            prompts.append("当前这条用户消息依赖实时天气，请优先调用 `get_current_weather`；如果用户没有给出地点，优先判断是否需要当前位置。")
        }

        if isNearbyRecommendationQuestion(normalizedText) {
            prompts.append("当前这条用户消息在询问去哪里玩或附近适合去什么地方，请优先调用 `get_current_location`；如果问题还涉及明天、周末或未来几天是否适合出门，再补充调用 `get_weather_forecast`。")
        }

        return prompts
    }

    private func isCurrentDateTimeQuestion(_ text: String) -> Bool {
        let keywords = [
            "今天几号",
            "今天几月几号",
            "今天几月几日",
            "今天星期几",
            "几月几号",
            "几月几日",
            "星期几",
            "周几",
            "礼拜几",
            "现在几点",
            "当前时间",
            "现在时间",
            "当前日期",
            "时区"
        ]

        return keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func isCurrentLocationQuestion(_ text: String) -> Bool {
        let keywords = [
            "我在哪",
            "我在哪里",
            "当前位置",
            "我的位置"
        ]

        return containsAny(text, keywords: keywords)
    }

    private func isWeatherQuestion(_ text: String) -> Bool {
        let keywords = [
            "天气",
            "温度",
            "下雨",
            "降雨",
            "雨吗",
            "冷不冷",
            "热不热"
        ]

        return containsAny(text, keywords: keywords)
    }

    private func isForecastWeatherQuestion(_ text: String) -> Bool {
        let forecastKeywords = [
            "预报",
            "明天",
            "后天",
            "大后天",
            "未来",
            "未来几天",
            "未来三天",
            "这周",
            "本周",
            "周末",
            "下周",
            "接下来几天"
        ]

        return containsAny(text, keywords: forecastKeywords)
            && (isWeatherQuestion(text) || isNearbyRecommendationQuestion(text) || text.localizedCaseInsensitiveContains("适合出门"))
    }

    private func isNearbyRecommendationQuestion(_ text: String) -> Bool {
        let keywords = [
            "去哪里玩",
            "去哪玩",
            "附近玩",
            "附近有什么好玩的",
            "周边玩",
            "周边有什么好玩的",
            "附近逛",
            "周边逛",
            "适合出去玩",
            "适合出门",
            "附近有什么地方可以去"
        ]

        return containsAny(text, keywords: keywords)
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func parseServerError(statusCode: Int, data: Data) -> OpenAIChatServiceError {
        if let apiError = try? jsonDecoder.decode(ErrorBody.self, from: data),
           let message = apiError.error?.message ?? apiError.message,
           message.isEmpty == false {
            return .serverError(statusCode: statusCode, message: message)
        }

        let rawText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = rawText?.isEmpty == false
            ? rawText!
            : "请求失败，状态码 \(statusCode)"
        return .serverError(statusCode: statusCode, message: message)
    }

    private func shouldRetry(after error: Error) -> Bool {
        if case OpenAIChatServiceError.timeout = error {
            return true
        }

        if case let OpenAIChatServiceError.serverError(statusCode, _) = error {
            return [408, 429, 500, 502, 503, 504].contains(statusCode)
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost].contains(nsError.code)
    }

    private func makeURLSession(timeoutInterval: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private func truncateForLog(_ value: String, limit: Int = 400) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "..."
    }
}
