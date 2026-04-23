import Foundation

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if condition() {
        print("PASS: \(message)")
        return true
    }

    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

@main
struct MarkdownAgentIntegrationTests {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let apiKey = environment["OPENAI_API_KEY"], apiKey.isEmpty == false,
              let baseURL = environment["OPENAI_BASE_URL"], baseURL.isEmpty == false,
              let model = environment["OPENAI_MODEL"], model.isEmpty == false else {
            fputs("Missing OPENAI_API_KEY / OPENAI_BASE_URL / OPENAI_MODEL\n", stderr)
            exit(1)
        }

        let configuration = OpenAIModelConfiguration(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model
        )
        let service = try MarkdownDocumentAgentService(configuration: configuration)

        try await runFullDocumentCase(service: service)
        try await runSelectionCase(service: service)
        try await runLineRangeCase(service: service)

        print("Markdown agent integration tests completed.")
    }

    private static func runFullDocumentCase(service: MarkdownDocumentAgentService) async throws {
        let content = """
        # Travel Brief

        ## Plan
        - Friday: arrive in Hangzhou
        - Saturday: visit the lake
        """

        let proposal = try await service.proposeEdit(
            fileName: "travel-brief.md",
            content: content,
            instruction: "在文档末尾补充一个 `## Risks` 小节，列出两条简短风险提示。",
            scope: .fullDocument(totalLines: MarkdownLineLocator.lineCount(in: content)),
            timeoutInterval: 90
        )

        let diff = MarkdownDiffEngine.makeDiff(original: content, updated: proposal.updatedMarkdown)
        expect(diff.hasChanges, "full document case returns actual changes")
        expect(proposal.summary.isEmpty == false, "full document case returns summary")
        expect(proposal.updatedMarkdown.contains("## Risks"), "full document case adds requested section")
    }

    private static func runSelectionCase(service: MarkdownDocumentAgentService) async throws {
        let content = """
        # Weekly Update

        ## Overview
        本周工作推进顺利，但是跨团队沟通还不够及时。

        ## Next
        下周继续推进验收。
        """

        let selectedText = "本周工作推进顺利，但是跨团队沟通还不够及时。"
        let proposal = try await service.proposeEdit(
            fileName: "weekly-update.md",
            content: content,
            instruction: "把这句改成更正式的周报表达，但保留原意。",
            scope: .selection(selectedText: selectedText, lineRange: 4 ... 4),
            timeoutInterval: 90
        )

        let diff = MarkdownDiffEngine.makeDiff(original: content, updated: proposal.updatedMarkdown)
        expect(diff.hasChanges, "selection case returns actual changes")
        expect(proposal.updatedMarkdown.contains("## Overview"), "selection case keeps surrounding structure")
        expect(proposal.updatedMarkdown.contains("跨团队"), "selection case preserves key topic")
    }

    private static func runLineRangeCase(service: MarkdownDocumentAgentService) async throws {
        let content = """
        # Launch Tasks

        ## TODO
        - prepare release note
        - verify crash metrics
        - contact support team
        """

        let proposal = try await service.proposeEdit(
            fileName: "launch-tasks.md",
            content: content,
            instruction: "把指定行改成 GitHub checklist 风格，并保留原有任务语义。",
            scope: .lineRange(4 ... 6, excerpt: MarkdownLineLocator.excerpt(for: 4 ... 6, in: content), totalLines: MarkdownLineLocator.lineCount(in: content)),
            timeoutInterval: 90
        )

        let diff = MarkdownDiffEngine.makeDiff(original: content, updated: proposal.updatedMarkdown)
        expect(diff.hasChanges, "line range case returns actual changes")
        expect(proposal.updatedMarkdown.contains("- [ ]"), "line range case converts bullets into checklist")
        expect(proposal.updatedMarkdown.contains("crash"), "line range case preserves existing task semantics")
    }
}
