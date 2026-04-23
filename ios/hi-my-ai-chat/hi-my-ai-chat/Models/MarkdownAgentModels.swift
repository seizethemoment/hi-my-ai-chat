import Foundation

enum MarkdownAgentScopeMode: String, CaseIterable, Identifiable, Sendable {
    case fullDocument
    case selection
    case lineRange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullDocument:
            return "全文"
        case .selection:
            return "选区"
        case .lineRange:
            return "行号"
        }
    }
}

struct MarkdownEditorSelectionSnapshot: Equatable, Sendable {
    let rangeLocation: Int
    let rangeLength: Int
    let selectedText: String
    let lowerLine: Int?
    let upperLine: Int?

    static let empty = MarkdownEditorSelectionSnapshot(
        rangeLocation: 0,
        rangeLength: 0,
        selectedText: "",
        lowerLine: nil,
        upperLine: nil
    )

    var hasSelection: Bool {
        rangeLength > 0 && selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var lineRange: ClosedRange<Int>? {
        guard let lowerLine, let upperLine else { return nil }
        return min(lowerLine, upperLine) ... max(lowerLine, upperLine)
    }

    var lineLabel: String {
        guard let lineRange else { return "未选中内容" }
        if lineRange.lowerBound == lineRange.upperBound {
            return "第 \(lineRange.lowerBound) 行"
        }
        return "第 \(lineRange.lowerBound)-\(lineRange.upperBound) 行"
    }
}

enum MarkdownAgentEditScope: Equatable, Sendable {
    case fullDocument(totalLines: Int)
    case selection(selectedText: String, lineRange: ClosedRange<Int>)
    case lineRange(ClosedRange<Int>, excerpt: String, totalLines: Int)

    var label: String {
        switch self {
        case .fullDocument(let totalLines):
            return "全文（共 \(totalLines) 行）"
        case .selection(_, let lineRange):
            if lineRange.lowerBound == lineRange.upperBound {
                return "当前选区（第 \(lineRange.lowerBound) 行）"
            }
            return "当前选区（第 \(lineRange.lowerBound)-\(lineRange.upperBound) 行）"
        case .lineRange(let lineRange, _, _):
            if lineRange.lowerBound == lineRange.upperBound {
                return "指定行号（第 \(lineRange.lowerBound) 行）"
            }
            return "指定行号（第 \(lineRange.lowerBound)-\(lineRange.upperBound) 行）"
        }
    }

    var focusInstructions: String {
        switch self {
        case .fullDocument:
            return "这是一次全文修改，可以在保持 Markdown 结构正确的前提下重组全文。"
        case .selection(let selectedText, let lineRange):
            return """
            优先修改当前选区，尽量不要改动选区外内容。
            选区行号：\(lineRange.lowerBound)-\(lineRange.upperBound)
            选区原文：
            \(selectedText)
            """
        case .lineRange(let lineRange, let excerpt, _):
            return """
            优先修改指定行范围，尽量不要改动范围外内容。
            指定行号：\(lineRange.lowerBound)-\(lineRange.upperBound)
            该范围原文：
            \(excerpt)
            """
        }
    }
}

struct MarkdownAgentProposal: Equatable, Sendable {
    let summary: String
    let scopeLabel: String
    let updatedMarkdown: String
}

struct MarkdownAgentDiffLine: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case context
        case addition
        case deletion
    }

    let id = UUID()
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

struct MarkdownAgentDiffHunk: Identifiable, Equatable, Sendable {
    let id = UUID()
    let header: String
    let lines: [MarkdownAgentDiffLine]
}

struct MarkdownAgentDiffStats: Equatable, Sendable {
    let additionCount: Int
    let deletionCount: Int
    let hunkCount: Int

    var summaryText: String {
        "新增 \(additionCount) 行 · 删除 \(deletionCount) 行 · \(hunkCount) 处变更"
    }
}

struct MarkdownAgentDiff: Equatable, Sendable {
    let stats: MarkdownAgentDiffStats
    let hunks: [MarkdownAgentDiffHunk]

    var hasChanges: Bool {
        stats.additionCount > 0 || stats.deletionCount > 0
    }
}

struct MarkdownAgentPendingProposal: Identifiable, Equatable, Sendable {
    let id = UUID()
    let instruction: String
    let scope: MarkdownAgentEditScope
    let originalMarkdown: String
    let proposal: MarkdownAgentProposal
    let diff: MarkdownAgentDiff
}

struct MarkdownAgentActivityEntry: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case info
        case success
        case warning
        case failure
    }

    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let title: String
    let detail: String
}

struct MarkdownAgentRevisionSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let fileName: String
    let instruction: String
    let summary: String
    let content: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fileName: String,
        instruction: String,
        summary: String,
        content: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.instruction = instruction
        self.summary = summary
        self.content = content
    }
}

enum MarkdownAgentError: LocalizedError {
    case emptyDocument
    case missingSelection
    case invalidLineRange
    case lineRangeOutOfBounds(maxLine: Int)
    case emptyProposal
    case unchangedProposal
    case failedToLoadHistory
    case failedToSaveHistory

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "Markdown 文档内容为空，无法生成提案。"
        case .missingSelection:
            return "当前没有选中文本，请先选中要修改的内容，或切换到全文/行号模式。"
        case .invalidLineRange:
            return "行号格式无效，请输入如 12-18 或 24。"
        case .lineRangeOutOfBounds(let maxLine):
            return "行号超出范围，当前文档共 \(maxLine) 行。"
        case .emptyProposal:
            return "模型没有返回有效的 Markdown 提案。"
        case .unchangedProposal:
            return "模型返回的内容与原文一致，没有可写回的修改。"
        case .failedToLoadHistory:
            return "读取 Markdown agent 历史记录失败。"
        case .failedToSaveHistory:
            return "保存 Markdown agent 历史记录失败。"
        }
    }
}
