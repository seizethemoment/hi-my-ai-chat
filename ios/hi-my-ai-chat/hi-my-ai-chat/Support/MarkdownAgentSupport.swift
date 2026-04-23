import Foundation

enum MarkdownLineLocator {
    static func normalizedLines(for text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.isEmpty == false else { return [] }
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func lineCount(in text: String) -> Int {
        max(normalizedLines(for: text).count, 1)
    }

    static func parseLineRange(
        from rawValue: String,
        maxLine: Int
    ) throws -> ClosedRange<Int> {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "~", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "")

        guard trimmed.isEmpty == false else {
            throw MarkdownAgentError.invalidLineRange
        }

        let parts = trimmed
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)

        let values = parts.compactMap(Int.init)
        guard values.count == parts.count, values.isEmpty == false, values.count <= 2 else {
            throw MarkdownAgentError.invalidLineRange
        }

        let lowerBound = values.min() ?? 0
        let upperBound = values.max() ?? 0
        guard lowerBound >= 1, upperBound <= maxLine else {
            throw MarkdownAgentError.lineRangeOutOfBounds(maxLine: maxLine)
        }

        return lowerBound ... upperBound
    }

    static func excerpt(for lineRange: ClosedRange<Int>, in text: String) -> String {
        let lines = normalizedLines(for: text)
        guard lines.isEmpty == false else { return "" }

        let lowerIndex = max(lineRange.lowerBound - 1, 0)
        let upperIndex = min(lineRange.upperBound - 1, lines.count - 1)
        guard lowerIndex <= upperIndex else { return "" }

        return lines[lowerIndex ... upperIndex].joined(separator: "\n")
    }

    static func numberedDocument(_ text: String) -> String {
        let lines = normalizedLines(for: text)
        guard lines.isEmpty == false else { return "1 | " }

        return lines.enumerated().map { index, line in
            "\(index + 1) | \(line)"
        }.joined(separator: "\n")
    }

    static func makeSelectionSnapshot(text: String, selectedRange: NSRange) -> MarkdownEditorSelectionSnapshot {
        let nsText = text as NSString
        let clampedLocation = min(max(selectedRange.location, 0), nsText.length)
        let clampedLength = min(max(selectedRange.length, 0), nsText.length - clampedLocation)
        let range = NSRange(location: clampedLocation, length: clampedLength)
        let selectedText = range.length > 0 ? nsText.substring(with: range) : ""

        let lowerLine = lineNumber(atUTF16Offset: range.location, in: nsText)
        let upperLocation = range.length > 0 ? range.location + range.length : range.location
        let upperLine = lineNumber(atUTF16Offset: upperLocation, in: nsText)

        return MarkdownEditorSelectionSnapshot(
            rangeLocation: range.location,
            rangeLength: range.length,
            selectedText: selectedText,
            lowerLine: lowerLine,
            upperLine: upperLine
        )
    }

    private static func lineNumber(atUTF16Offset offset: Int, in text: NSString) -> Int? {
        guard text.length > 0 else { return 1 }
        let clampedOffset = min(max(offset, 0), text.length)
        let prefix = text.substring(to: clampedOffset)
        return prefix.reduce(into: 1) { partialResult, character in
            if character == "\n" {
                partialResult += 1
            }
        }
    }
}

enum MarkdownDiffEngine {
    static func makeDiff(
        original: String,
        updated: String,
        contextLineCount: Int = 2
    ) -> MarkdownAgentDiff {
        let oldLines = MarkdownLineLocator.normalizedLines(for: original)
        let newLines = MarkdownLineLocator.normalizedLines(for: updated)
        let difference = newLines.difference(from: oldLines)
        let renderedLines = renderLines(
            oldLines: oldLines,
            newLines: newLines,
            difference: difference
        )

        let additionCount = renderedLines.filter { $0.kind == .addition }.count
        let deletionCount = renderedLines.filter { $0.kind == .deletion }.count

        guard additionCount > 0 || deletionCount > 0 else {
            return MarkdownAgentDiff(
                stats: MarkdownAgentDiffStats(additionCount: 0, deletionCount: 0, hunkCount: 0),
                hunks: []
            )
        }

        let hunks = makeHunks(from: renderedLines, contextLineCount: contextLineCount)
        return MarkdownAgentDiff(
            stats: MarkdownAgentDiffStats(
                additionCount: additionCount,
                deletionCount: deletionCount,
                hunkCount: hunks.count
            ),
            hunks: hunks
        )
    }

    private static func renderLines(
        oldLines: [String],
        newLines: [String],
        difference: CollectionDifference<String>
    ) -> [MarkdownAgentDiffLine] {
        var removalsByOffset: [Int: [String]] = [:]
        var insertionsByOffset: [Int: [String]] = [:]

        for change in difference {
            switch change {
            case .remove(let offset, let element, _):
                removalsByOffset[offset, default: []].append(element)
            case .insert(let offset, let element, _):
                insertionsByOffset[offset, default: []].append(element)
            }
        }

        var renderedLines: [MarkdownAgentDiffLine] = []
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            let removalOffset = oldIndex
            if let removals = removalsByOffset[removalOffset], removals.isEmpty == false {
                for removedLine in removals {
                    renderedLines.append(
                        MarkdownAgentDiffLine(
                            kind: .deletion,
                            oldLineNumber: oldIndex + 1,
                            newLineNumber: nil,
                            text: removedLine
                        )
                    )
                    oldIndex += 1
                }
                removalsByOffset.removeValue(forKey: removalOffset)
                continue
            }

            let insertionOffset = newIndex
            if let insertions = insertionsByOffset[insertionOffset], insertions.isEmpty == false {
                for insertedLine in insertions {
                    renderedLines.append(
                        MarkdownAgentDiffLine(
                            kind: .addition,
                            oldLineNumber: nil,
                            newLineNumber: newIndex + 1,
                            text: insertedLine
                        )
                    )
                    newIndex += 1
                }
                insertionsByOffset.removeValue(forKey: insertionOffset)
                continue
            }

            guard oldIndex < oldLines.count, newIndex < newLines.count else {
                if oldIndex < oldLines.count {
                    renderedLines.append(
                        MarkdownAgentDiffLine(
                            kind: .deletion,
                            oldLineNumber: oldIndex + 1,
                            newLineNumber: nil,
                            text: oldLines[oldIndex]
                        )
                    )
                    oldIndex += 1
                } else if newIndex < newLines.count {
                    renderedLines.append(
                        MarkdownAgentDiffLine(
                            kind: .addition,
                            oldLineNumber: nil,
                            newLineNumber: newIndex + 1,
                            text: newLines[newIndex]
                        )
                    )
                    newIndex += 1
                }
                continue
            }

            renderedLines.append(
                MarkdownAgentDiffLine(
                    kind: .context,
                    oldLineNumber: oldIndex + 1,
                    newLineNumber: newIndex + 1,
                    text: oldLines[oldIndex]
                )
            )
            oldIndex += 1
            newIndex += 1
        }

        return renderedLines
    }

    private static func makeHunks(
        from lines: [MarkdownAgentDiffLine],
        contextLineCount: Int
    ) -> [MarkdownAgentDiffHunk] {
        let changedIndices = lines.indices.filter { lines[$0].kind != .context }
        guard changedIndices.isEmpty == false else { return [] }

        var windows: [ClosedRange<Int>] = []
        for index in changedIndices {
            let lowerBound = max(0, index - contextLineCount)
            let upperBound = min(lines.count - 1, index + contextLineCount)
            let window = lowerBound ... upperBound

            if let lastWindow = windows.last, window.lowerBound <= lastWindow.upperBound + 1 {
                windows[windows.count - 1] = lastWindow.lowerBound ... max(lastWindow.upperBound, window.upperBound)
            } else {
                windows.append(window)
            }
        }

        return windows.map { window in
            let hunkLines = Array(lines[window])
            return MarkdownAgentDiffHunk(
                header: makeHunkHeader(for: hunkLines),
                lines: hunkLines
            )
        }
    }

    private static func makeHunkHeader(for lines: [MarkdownAgentDiffLine]) -> String {
        let oldNumbers = lines.compactMap(\.oldLineNumber)
        let newNumbers = lines.compactMap(\.newLineNumber)
        let oldLabel = rangeLabel(from: oldNumbers)
        let newLabel = rangeLabel(from: newNumbers)
        return "@@ -\(oldLabel) +\(newLabel) @@"
    }

    private static func rangeLabel(from lineNumbers: [Int]) -> String {
        guard let first = lineNumbers.first, let last = lineNumbers.last else {
            return "0"
        }

        if first == last {
            return "\(first)"
        }
        return "\(first),\(last - first + 1)"
    }
}

enum MarkdownRevisionStore {
    private static let directoryName = "markdown_agent_revisions"
    private static let maxSnapshotCount = 10

    private static var baseDirectory: URL {
        ChatDocumentStore.baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func loadSnapshots(for attachment: ChatDocumentAttachment) throws -> [MarkdownAgentRevisionSnapshot] {
        do {
            try ensureBaseDirectory()
            let url = historyURL(for: attachment)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([MarkdownAgentRevisionSnapshot].self, from: data)
        } catch {
            throw MarkdownAgentError.failedToLoadHistory
        }
    }

    static func hasSnapshots(for attachment: ChatDocumentAttachment) -> Bool {
        guard let snapshots = try? loadSnapshots(for: attachment) else {
            return false
        }
        return snapshots.isEmpty == false
    }

    static func push(
        snapshot: MarkdownAgentRevisionSnapshot,
        for attachment: ChatDocumentAttachment
    ) throws {
        var snapshots = try loadSnapshots(for: attachment)
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshotCount {
            snapshots.removeFirst(snapshots.count - maxSnapshotCount)
        }
        try persist(snapshots: snapshots, for: attachment)
    }

    static func popLatest(for attachment: ChatDocumentAttachment) throws -> MarkdownAgentRevisionSnapshot? {
        var snapshots = try loadSnapshots(for: attachment)
        let latest = snapshots.popLast()
        try persist(snapshots: snapshots, for: attachment)
        return latest
    }

    private static func persist(
        snapshots: [MarkdownAgentRevisionSnapshot],
        for attachment: ChatDocumentAttachment
    ) throws {
        do {
            try ensureBaseDirectory()
            let data = try JSONEncoder().encode(snapshots)
            try data.write(to: historyURL(for: attachment), options: [.atomic])
        } catch {
            throw MarkdownAgentError.failedToSaveHistory
        }
    }

    private static func historyURL(for attachment: ChatDocumentAttachment) -> URL {
        baseDirectory.appendingPathComponent("\(attachment.id.uuidString).json", isDirectory: false)
    }

    private static func ensureBaseDirectory() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
