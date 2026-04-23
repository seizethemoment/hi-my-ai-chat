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

func makeAttachment() -> ChatDocumentAttachment {
    ChatDocumentAttachment(
        id: UUID(),
        fileName: "agent-test.md",
        mimeType: "text/markdown",
        kind: .markdown,
        storageRelativePath: "agent-test-\(UUID().uuidString).md",
        fileSizeBytes: 0
    )
}

@main
struct MarkdownAgentSmokeTests {
    static func main() throws {
        let sample = """
        # Weekly Note

        ## Risks
        - Timeline is tight
        - QA bandwidth is limited

        ## Next Step
        Ship the first beta.
        """

        let range = try MarkdownLineLocator.parseLineRange(from: "4-5", maxLine: MarkdownLineLocator.lineCount(in: sample))
        expect(range == 4 ... 5, "line range parser supports closed ranges")

        let singleLine = try MarkdownLineLocator.parseLineRange(from: "7", maxLine: MarkdownLineLocator.lineCount(in: sample))
        expect(singleLine == 7 ... 7, "line range parser supports single line")

        let excerpt = MarkdownLineLocator.excerpt(for: 4 ... 5, in: sample)
        expect(excerpt.contains("Timeline is tight"), "excerpt extracts requested lines")
        expect(excerpt.contains("QA bandwidth is limited"), "excerpt keeps second line")

        let selectionRange = (sample as NSString).range(of: "## Risks\n- Timeline is tight")
        let snapshot = MarkdownLineLocator.makeSelectionSnapshot(text: sample, selectedRange: selectionRange)
        expect(snapshot.hasSelection, "selection snapshot marks non-empty selection")
        expect(snapshot.lineRange == 3 ... 4, "selection snapshot computes line numbers")

        let updated = """
        # Weekly Note

        ## Risks
        - Timeline is tight
        - QA bandwidth is limited
        - Release checklist needs one more review

        ## Next Step
        Ship the first beta.
        """

        let diff = MarkdownDiffEngine.makeDiff(original: sample, updated: updated)
        expect(diff.hasChanges, "diff engine detects additions")
        expect(diff.stats.additionCount == 1, "diff engine reports added line count")
        expect(diff.hunks.isEmpty == false, "diff engine produces hunks")

        let attachment = makeAttachment()
        let snapshotRecord = MarkdownAgentRevisionSnapshot(
            fileName: attachment.fileName,
            instruction: "补充一个风险项",
            summary: "新增一条风险说明",
            content: sample
        )
        try MarkdownRevisionStore.push(snapshot: snapshotRecord, for: attachment)
        expect(MarkdownRevisionStore.hasSnapshots(for: attachment), "revision store reports available snapshots")

        let restored = try MarkdownRevisionStore.popLatest(for: attachment)
        expect(restored?.content == sample, "revision store restores latest snapshot")
        expect(MarkdownRevisionStore.hasSnapshots(for: attachment) == false, "revision store removes popped snapshot")

        print("Markdown agent smoke tests completed.")
    }
}
