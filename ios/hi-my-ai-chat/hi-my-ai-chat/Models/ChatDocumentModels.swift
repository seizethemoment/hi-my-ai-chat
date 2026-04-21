import Foundation
import PDFKit
import UniformTypeIdentifiers

struct ChatDocumentAttachment: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case markdown
        case pdf
        case other

        var labelText: String {
            switch self {
            case .markdown:
                return "MARKDOWN"
            case .pdf:
                return "PDF"
            case .other:
                return "OTHERS"
            }
        }

        var systemImage: String {
            switch self {
            case .markdown:
                return "doc.text"
            case .pdf:
                return "doc.richtext"
            case .other:
                return "doc"
            }
        }

        var contentTypeDescription: String {
            switch self {
            case .markdown:
                return "Markdown 文档"
            case .pdf:
                return "PDF 文档"
            case .other:
                return "文件"
            }
        }
    }

    let id: UUID
    let fileName: String
    let mimeType: String
    let kind: Kind
    let storageRelativePath: String
    let pageCount: Int?
    let fileSizeBytes: Int64

    init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        kind: Kind,
        storageRelativePath: String,
        pageCount: Int? = nil,
        fileSizeBytes: Int64
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.kind = kind
        self.storageRelativePath = storageRelativePath
        self.pageCount = pageCount
        self.fileSizeBytes = fileSizeBytes
    }

    var fileExtensionLabel: String {
        kind.labelText
    }

    var resolvedURL: URL {
        ChatDocumentStore.baseDirectory.appendingPathComponent(storageRelativePath)
    }

    var truncatedDisplayName: String {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let trimmedBaseName = String(baseName.prefix(26))
        guard fileExtension.isEmpty == false else {
            return trimmedBaseName
        }

        return trimmedBaseName + (baseName.count > 26 ? "…" : "") + "." + fileExtension
    }

    var secondaryMetadataText: String {
        var components = [fileExtensionLabel]
        if let pageCount {
            components.append("\(pageCount) 页")
        }
        components.append(ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file))
        return components.joined(separator: " · ")
    }
}

enum ChatDocumentStoreError: LocalizedError {
    case unsupportedFile
    case failedToRead
    case failedToWrite

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "当前仅支持导入 Markdown 或 PDF 文件。"
        case .failedToRead:
            return "读取文件失败，请重试。"
        case .failedToWrite:
            return "写入文件失败，请重试。"
        }
    }
}

enum ChatDocumentStore {
    private static let directoryName = "chat_documents"

    static var baseDirectory: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documentsDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func importPickedFiles(from urls: [URL]) throws -> [ChatDocumentAttachment] {
        try ensureBaseDirectory()
        var attachments: [ChatDocumentAttachment] = []
        attachments.reserveCapacity(urls.count)

        for url in urls {
            try attachments.append(importPickedFile(from: url))
        }

        return attachments
    }

    static func loadTextContent(for attachment: ChatDocumentAttachment, limit: Int? = nil) -> String? {
        switch attachment.kind {
        case .markdown:
            guard let content = try? String(contentsOf: attachment.resolvedURL, encoding: .utf8) else {
                return nil
            }
            return truncated(content, limit: limit)
        case .pdf:
            guard let document = PDFDocument(url: attachment.resolvedURL) else {
                return nil
            }
            return truncated(document.string ?? "", limit: limit)
        case .other:
            return nil
        }
    }

    static func updateMarkdownFile(for attachment: ChatDocumentAttachment, content: String) throws {
        guard attachment.kind == .markdown else {
            throw ChatDocumentStoreError.unsupportedFile
        }

        do {
            try ensureBaseDirectory()
            try content.write(to: attachment.resolvedURL, atomically: true, encoding: .utf8)
        } catch {
            throw ChatDocumentStoreError.failedToWrite
        }
    }

    private static func importPickedFile(from url: URL) throws -> ChatDocumentAttachment {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        let kind = documentKind(for: fileExtension)
        guard kind != .other else {
            throw ChatDocumentStoreError.unsupportedFile
        }
        let destinationFileName = UUID().uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        let destinationURL = baseDirectory.appendingPathComponent(destinationFileName)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            throw ChatDocumentStoreError.failedToRead
        }

        let pageCount: Int?
        switch kind {
        case .pdf:
            pageCount = PDFDocument(url: destinationURL)?.pageCount
        case .markdown, .other:
            pageCount = nil
        }

        let fileSize = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let mimeType = mimeType(for: fileExtension)

        return ChatDocumentAttachment(
            fileName: fileName,
            mimeType: mimeType,
            kind: kind,
            storageRelativePath: destinationFileName,
            pageCount: pageCount,
            fileSizeBytes: fileSize
        )
    }

    private static func documentKind(for fileExtension: String) -> ChatDocumentAttachment.Kind {
        switch fileExtension {
        case "md", "markdown":
            return .markdown
        case "pdf":
            return .pdf
        default:
            return .other
        }
    }

    private static func mimeType(for fileExtension: String) -> String {
        if let contentType = UTType(filenameExtension: fileExtension)?.preferredMIMEType {
            return contentType
        }

        switch fileExtension {
        case "md", "markdown":
            return "text/markdown"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }

    private static func ensureBaseDirectory() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func truncated(_ text: String, limit: Int?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let limit, trimmed.count > limit else {
            return trimmed
        }

        return String(trimmed.prefix(limit)) + "…"
    }
}
