import Foundation

enum OpenAIChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
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
        }
    }
}

struct OpenAIChatService: Sendable {
    private struct RequestBody: Encodable, Sendable {
        let model: String
        let messages: [RequestMessage]
        let temperature: Double
        let stream: Bool
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
        let content: Content
    }

    private struct ResponseMessage: Decodable, Sendable {
        let content: String
    }

    private struct ResponseBody: Decodable, Sendable {
        struct Choice: Decodable, Sendable {
            let message: ResponseMessage
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

    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let jsonDecoder: JSONDecoder

    init(
        configuration: OpenAIModelConfiguration? = nil,
        systemPrompt: String = OpenAISettings.systemPrompt
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
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func reply(for conversation: [OpenAIChatTurn]) async throws -> String {
        let request = try makeRequest(for: conversation, stream: false, timeoutInterval: 30)
        let session = makeURLSession(timeoutInterval: 30)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIChatServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw parseServerError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoded = try jsonDecoder.decode(ResponseBody.self, from: data)
        guard let reply = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              reply.isEmpty == false else {
            throw OpenAIChatServiceError.emptyReply
        }

        return reply
    }

    func streamReply(
        for conversation: [OpenAIChatTurn],
        timeoutInterval: TimeInterval = 45,
        maxRetryCount: Int = 1,
        onRetry: (@Sendable (Int) async -> Void)? = nil,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let request = try makeRequest(for: conversation, stream: true, timeoutInterval: timeoutInterval)

        for attempt in 0...maxRetryCount {
            var streamedContent = ""

            do {
                let reply = try await consumeStream(
                    request: request,
                    timeoutInterval: timeoutInterval
                ) { delta in
                    streamedContent.append(delta)
                    await onDelta(delta)
                }

                return reply
            } catch {
                let shouldRetry = attempt < maxRetryCount
                    && streamedContent.isEmpty
                    && shouldRetry(after: error)

                guard shouldRetry else {
                    throw error
                }

                await onRetry?(attempt + 1)
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }

        throw OpenAIChatServiceError.invalidResponse
    }

    private func makeRequest(
        for conversation: [OpenAIChatTurn],
        stream: Bool,
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
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")

        let requestMessages =
            [RequestMessage(role: .system, content: .text(systemPrompt))] +
            conversation.map(makeRequestMessage)

        let body = RequestBody(
            model: model,
            messages: requestMessages,
            temperature: 0.7,
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func makeRequestMessage(for turn: OpenAIChatTurn) -> RequestMessage {
        guard turn.imageDataURLs.isEmpty == false else {
            return RequestMessage(role: turn.role, content: .text(turn.text))
        }

        let textParts = turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [RequestMessage.ContentPart.text(turn.text)]
        let imageParts = turn.imageDataURLs.map { url in
            RequestMessage.ContentPart.image(url: url)
        }

        return RequestMessage(
            role: turn.role,
            content: .parts(textParts + imageParts)
        )
    }

    private func consumeStream(
        request: URLRequest,
        timeoutInterval: TimeInterval,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let session = makeURLSession(timeoutInterval: timeoutInterval)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIChatServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            var errorData = Data()
            for try await line in bytes.lines {
                errorData.append(contentsOf: line.utf8)
                errorData.append(0x0A)
            }
            throw parseServerError(statusCode: httpResponse.statusCode, data: errorData)
        }

        var reply = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()

            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.isEmpty == false else { continue }
            guard trimmedLine.hasPrefix("data:") else { continue }

            let payload = trimmedLine
                .dropFirst(5)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if payload == "[DONE]" {
                break
            }

            guard let data = payload.data(using: .utf8),
                  let delta = extractDelta(from: data) else {
                continue
            }

            reply.append(delta)
            await onDelta(delta)
        }

        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReply.isEmpty == false else {
            throw OpenAIChatServiceError.emptyReply
        }

        return trimmedReply
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

    private func extractDelta(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonObject["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              content.isEmpty == false else {
            return nil
        }

        return content
    }

}
