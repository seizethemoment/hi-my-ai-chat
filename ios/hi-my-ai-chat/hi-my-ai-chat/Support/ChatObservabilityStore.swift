import Foundation

nonisolated struct ChatObservabilityUsage: Codable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var cachedPromptTokens: Int?
    var reasoningTokens: Int?

    var hasAnyValue: Bool {
        promptTokens != nil
            || completionTokens != nil
            || totalTokens != nil
            || cachedPromptTokens != nil
            || reasoningTokens != nil
    }

    mutating func accumulate(_ other: ChatObservabilityUsage) {
        promptTokens = Self.sum(promptTokens, other.promptTokens)
        completionTokens = Self.sum(completionTokens, other.completionTokens)
        totalTokens = Self.sum(totalTokens, other.totalTokens)
        cachedPromptTokens = Self.sum(cachedPromptTokens, other.cachedPromptTokens)
        reasoningTokens = Self.sum(reasoningTokens, other.reasoningTokens)
    }

    private static func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return lhs + rhs
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }
}

nonisolated struct ChatObservabilityModelRoundRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let roundIndex: Int
    let clientRequestID: String
    let startedAt: Date
    let durationMilliseconds: Int
    let statusCode: Int?
    let finishReason: String?
    let xRequestID: String?
    let toolCallCount: Int
    let toolNames: [String]
    let responseCharacterCount: Int
    let usage: ChatObservabilityUsage
    let errorDescription: String?

    var succeeded: Bool {
        errorDescription == nil && (statusCode.map { 200 ..< 300 ~= $0 } ?? true)
    }
}

nonisolated struct ChatObservabilityToolCallRecord: Identifiable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case success
        case failure
    }

    let id: UUID
    let roundIndex: Int
    let toolCallID: String
    let name: String
    let startedAt: Date
    let durationMilliseconds: Int
    let status: Status
    let argumentCharacterCount: Int
    let outputCharacterCount: Int
    let errorDescription: String?
}

nonisolated struct ChatObservabilityRunRecord: Identifiable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case success
        case failure
        case cancelled
    }

    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let status: Status
    let model: String
    let baseURLHost: String
    let latestUserMessagePreview: String
    let conversationTurnCount: Int
    let requestTurnCount: Int
    let inputCharacterCount: Int
    let inputImageCount: Int
    let outputCharacterCount: Int
    let retryCount: Int
    let totalDurationMilliseconds: Int
    let firstResponseMilliseconds: Int?
    let modelDurationMilliseconds: Int
    let toolDurationMilliseconds: Int
    let finalFinishReason: String?
    let lastStatusCode: Int?
    let lastXRequestID: String?
    let usage: ChatObservabilityUsage
    let rounds: [ChatObservabilityModelRoundRecord]
    let toolCalls: [ChatObservabilityToolCallRecord]
    let errorDescription: String?

    var toolFailureCount: Int {
        toolCalls.filter { $0.status == .failure }.count
    }
}

nonisolated struct ChatObservabilityDashboard: Sendable {
    static let empty = ChatObservabilityDashboard(records: [])

    let records: [ChatObservabilityRunRecord]

    private var latencyRecords: [ChatObservabilityRunRecord] {
        let nonCancelledRecords = records.filter { $0.status != .cancelled }
        return nonCancelledRecords.isEmpty ? records : nonCancelledRecords
    }

    var totalRuns: Int {
        records.count
    }

    var successCount: Int {
        records.filter { $0.status == .success }.count
    }

    var failureCount: Int {
        records.filter { $0.status == .failure }.count
    }

    var cancelledCount: Int {
        records.filter { $0.status == .cancelled }.count
    }

    var successRate: Double? {
        let completedCount = successCount + failureCount
        guard completedCount > 0 else { return nil }
        return Double(successCount) / Double(completedCount)
    }

    var averageLatencyMilliseconds: Int? {
        average(for: latencyRecords.map(\.totalDurationMilliseconds))
    }

    var p95LatencyMilliseconds: Int? {
        percentile95(for: latencyRecords.map(\.totalDurationMilliseconds))
    }

    var averageRounds: Double? {
        guard latencyRecords.isEmpty == false else { return nil }
        let totalRounds = latencyRecords.reduce(0) { $0 + $1.rounds.count }
        return Double(totalRounds) / Double(latencyRecords.count)
    }

    var totalToolCalls: Int {
        records.reduce(0) { $0 + $1.toolCalls.count }
    }

    var toolFailureRate: Double? {
        guard totalToolCalls > 0 else { return nil }
        let failedCalls = records.reduce(0) { $0 + $1.toolFailureCount }
        return Double(failedCalls) / Double(totalToolCalls)
    }

    var totalUsage: ChatObservabilityUsage {
        records.reduce(into: ChatObservabilityUsage()) { partialResult, record in
            partialResult.accumulate(record.usage)
        }
    }

    var topToolNames: [String] {
        let counts = records
            .flatMap(\.toolCalls)
            .reduce(into: [String: Int]()) { partialResult, toolCall in
                partialResult[toolCall.name, default: 0] += 1
            }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }

                return lhs.value > rhs.value
            }
            .prefix(3)
            .map(\.key)
    }

    private func average(for values: [Int]) -> Int? {
        guard values.isEmpty == false else { return nil }
        let total = values.reduce(0, +)
        return Int((Double(total) / Double(values.count)).rounded())
    }

    private func percentile95(for values: [Int]) -> Int? {
        guard values.isEmpty == false else { return nil }
        let sorted = values.sorted()
        let position = Int((Double(sorted.count - 1) * 0.95).rounded(.up))
        return sorted[min(max(position, 0), sorted.count - 1)]
    }
}

nonisolated struct ChatObservabilityRunBuilder: Sendable {
    private let startedAt: Date
    private let runID: UUID
    private let model: String
    private let baseURLHost: String
    private let latestUserMessagePreview: String
    private let conversationTurnCount: Int
    private let requestTurnCount: Int
    private let inputCharacterCount: Int
    private let inputImageCount: Int

    private var retryCount = 0
    private var firstResponseMilliseconds: Int?
    private var totalUsage = ChatObservabilityUsage()
    private var rounds: [ChatObservabilityModelRoundRecord] = []
    private var toolCalls: [ChatObservabilityToolCallRecord] = []
    private var finalFinishReason: String?
    private var lastStatusCode: Int?
    private var lastXRequestID: String?

    init(
        model: String,
        baseURL: URL,
        conversation: [OpenAIChatTurn],
        requestTurnCount: Int
    ) {
        self.startedAt = Date()
        self.runID = UUID()
        self.model = model
        self.baseURLHost = baseURL.host ?? baseURL.absoluteString
        self.latestUserMessagePreview = Self.latestUserMessagePreview(from: conversation)
        self.conversationTurnCount = conversation.filter { $0.role != .system }.count
        self.requestTurnCount = requestTurnCount
        self.inputCharacterCount = conversation
            .filter { $0.role != .system }
            .reduce(0) { $0 + $1.text.count }
        self.inputImageCount = conversation
            .filter { $0.role == .user }
            .reduce(0) { $0 + $1.imageDataURLs.count }
    }

    mutating func recordRetry(_ retryCount: Int) {
        self.retryCount = max(self.retryCount, retryCount)
    }

    mutating func recordRound(
        roundIndex: Int,
        clientRequestID: String,
        startedAt: Date,
        durationMilliseconds: Int,
        statusCode: Int?,
        finishReason: String?,
        xRequestID: String?,
        toolNames: [String],
        responseCharacterCount: Int,
        usage: ChatObservabilityUsage,
        errorDescription: String?
    ) {
        if firstResponseMilliseconds == nil {
            firstResponseMilliseconds = durationMilliseconds
        }

        let round = ChatObservabilityModelRoundRecord(
            id: UUID(),
            roundIndex: roundIndex,
            clientRequestID: clientRequestID,
            startedAt: startedAt,
            durationMilliseconds: durationMilliseconds,
            statusCode: statusCode,
            finishReason: finishReason,
            xRequestID: xRequestID,
            toolCallCount: toolNames.count,
            toolNames: toolNames,
            responseCharacterCount: responseCharacterCount,
            usage: usage,
            errorDescription: errorDescription
        )

        rounds.append(round)
        totalUsage.accumulate(usage)
        finalFinishReason = finishReason ?? finalFinishReason
        lastStatusCode = statusCode ?? lastStatusCode
        lastXRequestID = xRequestID ?? lastXRequestID
    }

    mutating func recordToolCall(
        roundIndex: Int,
        toolCallID: String,
        name: String,
        startedAt: Date,
        durationMilliseconds: Int,
        argumentsJSON: String,
        output: String,
        errorDescription: String?
    ) {
        let toolCall = ChatObservabilityToolCallRecord(
            id: UUID(),
            roundIndex: roundIndex,
            toolCallID: toolCallID,
            name: name,
            startedAt: startedAt,
            durationMilliseconds: durationMilliseconds,
            status: errorDescription == nil ? .success : .failure,
            argumentCharacterCount: argumentsJSON.count,
            outputCharacterCount: output.count,
            errorDescription: errorDescription
        )

        toolCalls.append(toolCall)
    }

    func build(status: ChatObservabilityRunRecord.Status, outputText: String?, errorDescription: String?) -> ChatObservabilityRunRecord {
        let finishedAt = Date()
        let modelDuration = rounds.reduce(0) { $0 + $1.durationMilliseconds }
        let toolDuration = toolCalls.reduce(0) { $0 + $1.durationMilliseconds }

        return ChatObservabilityRunRecord(
            id: runID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: status,
            model: model,
            baseURLHost: baseURLHost,
            latestUserMessagePreview: latestUserMessagePreview,
            conversationTurnCount: conversationTurnCount,
            requestTurnCount: requestTurnCount,
            inputCharacterCount: inputCharacterCount,
            inputImageCount: inputImageCount,
            outputCharacterCount: outputText?.count ?? 0,
            retryCount: retryCount,
            totalDurationMilliseconds: max(Int(finishedAt.timeIntervalSince(startedAt) * 1_000), 0),
            firstResponseMilliseconds: firstResponseMilliseconds,
            modelDurationMilliseconds: modelDuration,
            toolDurationMilliseconds: toolDuration,
            finalFinishReason: finalFinishReason,
            lastStatusCode: lastStatusCode,
            lastXRequestID: lastXRequestID,
            usage: totalUsage,
            rounds: rounds,
            toolCalls: toolCalls,
            errorDescription: errorDescription
        )
    }

    private static func latestUserMessagePreview(from conversation: [OpenAIChatTurn]) -> String {
        guard let latestUserTurn = conversation.last(where: { $0.role == .user }) else {
            return "无用户消息"
        }

        let trimmedText = latestUserTurn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var fragments: [String] = []

        if trimmedText.isEmpty == false {
            fragments.append(String(trimmedText.prefix(48)))
        }

        if latestUserTurn.imageDataURLs.isEmpty == false {
            fragments.append("[\(latestUserTurn.imageDataURLs.count) 张图片]")
        }

        let preview = fragments.joined(separator: " ")
        return preview.isEmpty ? "无文本内容" : preview
    }
}

actor ChatObservabilityStore {
    static let shared = ChatObservabilityStore()

    private static let maxRecordCount = 120

    private let saveURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var records: [ChatObservabilityRunRecord]

    init(saveURL: URL? = nil) {
        self.saveURL = saveURL ?? Self.defaultSaveURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let data = try? Data(contentsOf: self.saveURL),
           let state = try? decoder.decode(PersistedChatObservabilityState.self, from: data) {
            self.records = state.records.sorted { $0.startedAt > $1.startedAt }
        } else {
            self.records = []
        }
    }

    func dashboard() -> ChatObservabilityDashboard {
        ChatObservabilityDashboard(records: records)
    }

    func record(_ record: ChatObservabilityRunRecord) {
        records.insert(record, at: 0)
        if records.count > Self.maxRecordCount {
            records = Array(records.prefix(Self.maxRecordCount))
        }
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func save() {
        let state = PersistedChatObservabilityState(records: records)

        do {
            let data = try encoder.encode(state)
            let directory = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: saveURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save observability records: \(error)")
        }
    }

    private static var defaultSaveURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documentsDirectory.appendingPathComponent("chat_observability.json")
    }
}

nonisolated private struct PersistedChatObservabilityState: Codable, Sendable {
    let records: [ChatObservabilityRunRecord]
}
