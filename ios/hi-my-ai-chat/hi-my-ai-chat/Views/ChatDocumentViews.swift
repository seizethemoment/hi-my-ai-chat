import PDFKit
import SwiftUI
import UIKit

struct ChatDocumentCardView: View {
    let attachment: ChatDocumentAttachment
    var width: CGFloat? = nil
    var minHeight: CGFloat = 112
    var removeAction: (() -> Void)? = nil
    var tapAction: (() -> Void)? = nil

    var body: some View {
        Group {
            if let tapAction {
                Button(action: tapAction) {
                    cardContent
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat_document_card_\(attachment.fileName)")
            } else {
                cardContent
                    .accessibilityIdentifier("chat_document_card_\(attachment.fileName)")
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconBackgroundColor)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: attachment.kind.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(iconForegroundColor)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(attachment.fileName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(attachment.secondaryMetadataText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.42))
                }

                Spacer(minLength: 0)
            }

            Text(attachment.fileExtensionLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(iconForegroundColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(iconForegroundColor.opacity(0.1))
                )
        }
        .padding(14)
        .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if let removeAction {
                Button(action: removeAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.62)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat_document_remove_button_\(attachment.fileName)")
                .padding(10)
            }
        }
    }

    private var iconBackgroundColor: Color {
        switch attachment.kind {
        case .markdown:
            return Color(red: 0.90, green: 0.95, blue: 1.0)
        case .pdf:
            return Color(red: 1.0, green: 0.94, blue: 0.94)
        case .other:
            return Color.black.opacity(0.05)
        }
    }

    private var iconForegroundColor: Color {
        switch attachment.kind {
        case .markdown:
            return Color(red: 0.12, green: 0.46, blue: 0.98)
        case .pdf:
            return Color(red: 0.85, green: 0.24, blue: 0.18)
        case .other:
            return Color.black.opacity(0.58)
        }
    }
}

struct ChatDocumentPreviewScreen: View {
    let attachment: ChatDocumentAttachment
    let makeChatService: () throws -> any ChatServiceProtocol

    var body: some View {
        switch attachment.kind {
        case .pdf:
            PDFDocumentPreviewScreen(attachment: attachment)
        case .markdown:
            MarkdownDocumentEditorScreen(
                attachment: attachment,
                makeChatService: makeChatService
            )
        case .other:
            GenericDocumentPreviewScreen(attachment: attachment)
        }
    }
}

private struct PDFDocumentPreviewScreen: View {
    let attachment: ChatDocumentAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var currentPageIndex = 1
    @State private var totalPageCount = 0
    @State private var isShareSheetPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.97, green: 0.97, blue: 0.965)
                .ignoresSafeArea()

            PDFPreviewRepresentable(
                attachment: attachment,
                currentPageIndex: $currentPageIndex,
                totalPageCount: $totalPageCount
            )
            .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack(spacing: 10) {
                    topIconButton(systemImage: "xmark", action: dismiss.callAsFunction)

                    Text("预览")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.86))
                        .frame(maxWidth: .infinity)

                    topIconButton(systemImage: "arrowshape.turn.up.right", action: { isShareSheetPresented = true })
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    Color.white.opacity(0.94)
                )

                HStack {
                    Text("\(max(currentPageIndex, 1))/\(max(totalPageCount, attachment.pageCount ?? 1))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                        )

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)

                Spacer()
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheetView(activityItems: [attachment.resolvedURL])
        }
    }

    @ViewBuilder
    private func topIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.88))

                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.9))
            }
            .frame(width: 56, height: 56)
        }
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
        .background(
            Circle()
                .fill(Color.white.opacity(0.001))
        )
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .buttonStyle(.plain)
        .accessibilityIdentifier(systemImage == "xmark" ? "pdf_document_close_button" : "pdf_document_share_button")
    }
}

private struct GenericDocumentPreviewScreen: View {
    let attachment: ChatDocumentAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var isShareSheetPresented = false
    @State private var extractedText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("generic_document_close_button")

                Spacer()

                Text(attachment.truncatedDisplayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button(action: { isShareSheetPresented = true }) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("generic_document_share_button")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                Text(extractedText.isEmpty ? "暂不支持预览该文件。" : extractedText)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .bottom)
        .task {
            extractedText = ChatDocumentStore.loadTextContent(for: attachment, limit: 20_000) ?? ""
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheetView(activityItems: [attachment.resolvedURL])
        }
    }
}

private struct MarkdownDocumentEditorScreen: View {
    let attachment: ChatDocumentAttachment
    let makeChatService: () throws -> any ChatServiceProtocol

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var savedDraft = ""
    @State private var aiInstruction = ""
    @State private var isEditing = false
    @State private var isApplyingAI = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isShareSheetPresented = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()

            Group {
                if isEditing {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )

                        MarkdownSyntaxTextEditor(text: $draft)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .accessibilityIdentifier("markdown_document_text_editor")

                        if draft.isEmpty {
                            Text("在这里继续编辑 Markdown…")
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.black.opacity(0.24))
                                .padding(.horizontal, 32)
                                .padding(.top, 26)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                } else {
                    ScrollView(showsIndicators: false) {
                        StreamingRichMessageView(
                            text: draft,
                            toolCalls: [],
                            foreground: Color.black.opacity(0.84)
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                MarkdownEditorAIDockView(
                    instruction: $aiInstruction,
                    canApplyAI: canApplyAI,
                    isApplyingAI: isApplyingAI,
                    statusMessage: statusMessage,
                    onApply: applyAIEdit
                )
            } else if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.46))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
            }
        }
        .task {
            if draft.isEmpty {
                loadDraft()
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheetView(activityItems: [attachment.resolvedURL])
        }
        .alert(
            "文档不可用",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        errorMessage = nil
                    }
                }
            ),
            actions: {
                Button("知道了", role: .cancel) {}
            },
            message: {
                Text(errorMessage ?? "")
            }
        )
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedInstruction: String {
        aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canApplyAI: Bool {
        isApplyingAI == false && trimmedDraft.isEmpty == false && trimmedInstruction.isEmpty == false
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: dismissWithAutoSave) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("markdown_document_close_button")

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.truncatedDisplayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .lineLimit(1)

                Text(isEditing ? "编辑模式" : "预览模式")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.34))
            }

            Spacer(minLength: 8)

            Button(action: { isShareSheetPresented = true }) {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("markdown_document_share_button")

            Button(action: { isEditing.toggle() }) {
                Text(isEditing ? "预览" : "编辑")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("markdown_document_toggle_button")

            if isEditing {
                Button(action: saveDraft) {
                    Text("保存")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.09, green: 0.48, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft == savedDraft || isApplyingAI)
                .opacity(draft == savedDraft || isApplyingAI ? 0.45 : 1)
                .accessibilityIdentifier("markdown_document_save_button")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.white)
    }

    private func loadDraft() {
        guard let content = ChatDocumentStore.loadTextContent(for: attachment) else {
            errorMessage = "读取 Markdown 文件失败。"
            return
        }

        draft = content
        savedDraft = content
    }

    private func saveDraft() {
        do {
            try ChatDocumentStore.updateMarkdownFile(for: attachment, content: draft)
            savedDraft = draft
            statusMessage = "已保存修改"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissWithAutoSave() {
        if draft != savedDraft {
            saveDraft()
        }
        dismiss()
    }

    private func applyAIEdit() {
        let instruction = aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard instruction.isEmpty == false, isApplyingAI == false else { return }

        let sourceDraft = draft
        guard sourceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            statusMessage = nil
            errorMessage = "Markdown 文档内容为空，无法发送给模型。"
            return
        }

        aiInstruction = ""
        isApplyingAI = true
        statusMessage = "模型正在修改文档…"

        Task {
            do {
                let service = try makeChatService()
                var streamedReply = ""
                let finalReply = try await service.streamReply(
                    for: markdownEditTurns(
                        fileName: attachment.fileName,
                        content: sourceDraft,
                        instruction: instruction
                    ),
                    timeoutInterval: 90,
                    maxRetryCount: 0,
                    onRetry: nil,
                    onEvent: { event in
                        guard case .textDelta(let delta) = event else { return }
                        streamedReply += delta
                        await MainActor.run {
                            draft = streamedReply
                        }
                    }
                )

                await MainActor.run {
                    let normalizedReply = finalReply.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard normalizedReply.isEmpty == false else {
                        draft = sourceDraft
                        isApplyingAI = false
                        statusMessage = nil
                        errorMessage = MarkdownEditorAIError.emptyResponse.localizedDescription
                        return
                    }

                    draft = normalizedReply
                    isApplyingAI = false
                    saveDraft()
                    statusMessage = "已应用 AI 修改"
                }
            } catch {
                await MainActor.run {
                    draft = sourceDraft
                    isApplyingAI = false
                    statusMessage = nil
                    errorMessage = "模型修改失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func markdownEditTurns(fileName: String, content: String, instruction: String) -> [OpenAIChatTurn] {
        [
            OpenAIChatTurn(
                role: .system,
                text: """
                你是一名 Markdown 文档编辑助手。
                你会收到一份 Markdown 文档全文和一条编辑指令。
                你必须直接返回修改后的完整 Markdown 文档，不要解释，不要使用代码块围栏，不要添加额外前言。
                如果用户只要求局部修改，也要返回更新后的完整文档。
                """,
                imageDataURLs: []
            ),
            OpenAIChatTurn(
                role: .user,
                text: """
                文件名：\(fileName)

                编辑要求：
                \(instruction)

                当前 Markdown 全文如下：
                \(content)
                """,
                imageDataURLs: []
            )
        ]
    }
}

private struct MarkdownEditorAIDockView: View {
    @Binding var instruction: String
    let canApplyAI: Bool
    let isApplyingAI: Bool
    let statusMessage: String?
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.46))
            }

            HStack(spacing: 12) {
                TextField("告诉模型如何修改这份 Markdown…", text: $instruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .tint(Color.black.opacity(0.84))
                    .lineLimit(1...3)
                    .submitLabel(.send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .accessibilityIdentifier("markdown_document_ai_instruction_input")

                Button(action: onApply) {
                    if isApplyingAI {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.white)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color(red: 0.09, green: 0.48, blue: 1.0))
                )
                .disabled(canApplyAI == false)
                .opacity(canApplyAI ? 1 : 0.45)
                .accessibilityIdentifier("markdown_document_ai_apply_button")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: -2)
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

private struct MarkdownSyntaxTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = UIColor.white
        textView.textColor = MarkdownEditorPalette.bodyUIColor
        textView.tintColor = MarkdownEditorPalette.accentUIColor
        textView.font = MarkdownEditorPalette.baseUIFont
        textView.overrideUserInterfaceStyle = .light
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = false
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 18, bottom: 28, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        context.coordinator.applyHighlighting(to: textView, text: text, preserveSelection: false)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncTextView(uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownSyntaxTextEditor
        private var isApplyingProgrammaticUpdate = false
        private var needsHighlightRefreshAfterMarkedText = false

        init(parent: MarkdownSyntaxTextEditor) {
            self.parent = parent
        }

        func syncTextView(_ textView: UITextView) {
            guard isApplyingProgrammaticUpdate == false else { return }

            textView.backgroundColor = UIColor.white
            textView.textColor = MarkdownEditorPalette.bodyUIColor
            textView.tintColor = MarkdownEditorPalette.accentUIColor

            if textView.attributedText.string != parent.text {
                applyHighlighting(to: textView, text: parent.text, preserveSelection: true)
            } else if needsHighlightRefreshAfterMarkedText, textView.markedTextRange == nil {
                applyHighlighting(to: textView, text: parent.text, preserveSelection: true)
                needsHighlightRefreshAfterMarkedText = false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
            }

            guard textView.markedTextRange == nil else {
                needsHighlightRefreshAfterMarkedText = true
                return
            }

            applyHighlighting(to: textView, text: textView.text, preserveSelection: true)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard needsHighlightRefreshAfterMarkedText, textView.markedTextRange == nil else { return }
            applyHighlighting(to: textView, text: textView.text, preserveSelection: true)
            needsHighlightRefreshAfterMarkedText = false
        }

        func applyHighlighting(to textView: UITextView, text: String, preserveSelection: Bool) {
            let selectedRange = preserveSelection ? textView.selectedRange : NSRange(location: text.utf16.count, length: 0)
            let highlighted = MarkdownSyntaxHighlighter.highlight(text)

            isApplyingProgrammaticUpdate = true
            textView.attributedText = highlighted
            textView.typingAttributes = MarkdownSyntaxHighlighter.baseTypingAttributes

            let clampedLocation = min(selectedRange.location, highlighted.length)
            let maxLength = max(0, highlighted.length - clampedLocation)
            textView.selectedRange = NSRange(
                location: clampedLocation,
                length: min(selectedRange.length, maxLength)
            )
            isApplyingProgrammaticUpdate = false
        }
    }
}

private enum MarkdownEditorPalette {
    static let bodyUIColor = UIColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    static let accentUIColor = UIColor(red: 0.09, green: 0.48, blue: 1.0, alpha: 1)
    static let headingOneUIColor = UIColor(red: 0.80, green: 0.38, blue: 0.13, alpha: 1)
    static let headingSecondaryUIColor = UIColor(red: 0.73, green: 0.41, blue: 0.15, alpha: 1)
    static let quoteUIColor = UIColor(red: 0.29, green: 0.46, blue: 0.62, alpha: 1)
    static let listMarkerUIColor = UIColor(red: 0.12, green: 0.46, blue: 0.98, alpha: 1)
    static let codeUIColor = UIColor(red: 0.35, green: 0.24, blue: 0.67, alpha: 1)
    static let codeBackgroundUIColor = UIColor(red: 0.95, green: 0.96, blue: 0.995, alpha: 1)
    static let fenceUIColor = UIColor(red: 0.59, green: 0.61, blue: 0.70, alpha: 1)
    static let linkUIColor = UIColor(red: 0.86, green: 0.39, blue: 0.20, alpha: 1)
    static let emphasisUIColor = UIColor(red: 0.82, green: 0.29, blue: 0.24, alpha: 1)
    static let baseUIFont = UIFont.monospacedSystemFont(ofSize: 16.5, weight: .regular)
}

private enum MarkdownSyntaxHighlighter {
    static let baseTypingAttributes: [NSAttributedString.Key: Any] = baseAttributes()

    private static let listMarkerRegex = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+\.)\s+"#)
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
    private static let linkRegex = try! NSRegularExpression(pattern: #"\[[^\]\n]+\]\([^\)\n]+\)"#)
    private static let strongRegex = try! NSRegularExpression(pattern: #"(?:\*\*|__)(?=\S)(.+?)(?<=\S)(?:\*\*|__)"#)
    private static let emphasisRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?=\S)(.+?)(?<=\S)\*(?!\*)|(?<!_)_(?=\S)(.+?)(?<=\S)_(?!_)"#)

    static func highlight(_ text: String) -> NSAttributedString {
        let nsText = text as NSString
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes())
        let wholeRange = NSRange(location: 0, length: nsText.length)
        let excludedRanges = applyLineLevelStyles(to: attributed, text: nsText, in: wholeRange)

        apply(regex: inlineCodeRegex, to: attributed, in: wholeRange, excluding: excludedRanges, attributes: inlineCodeAttributes())
        apply(regex: linkRegex, to: attributed, in: wholeRange, excluding: excludedRanges, attributes: linkAttributes())
        apply(regex: strongRegex, to: attributed, in: wholeRange, excluding: excludedRanges, attributes: strongAttributes())
        apply(regex: emphasisRegex, to: attributed, in: wholeRange, excluding: excludedRanges, attributes: emphasisAttributes())

        return attributed
    }

    private static func applyLineLevelStyles(
        to attributed: NSMutableAttributedString,
        text: NSString,
        in wholeRange: NSRange
    ) -> [NSRange] {
        var codeRanges: [NSRange] = []
        var isInsideCodeFence = false

        text.enumerateSubstrings(in: wholeRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.isEmpty == false else { return }

            if trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~") {
                attributed.addAttributes(codeFenceAttributes(), range: lineRange)
                codeRanges.append(lineRange)
                isInsideCodeFence.toggle()
                return
            }

            if isInsideCodeFence {
                attributed.addAttributes(codeBlockAttributes(), range: lineRange)
                codeRanges.append(lineRange)
                return
            }

            if let headingLevel = headingLevel(for: trimmedLine) {
                attributed.addAttributes(headingAttributes(level: headingLevel), range: lineRange)
                return
            }

            if trimmedLine.hasPrefix(">") {
                attributed.addAttributes(blockquoteAttributes(), range: lineRange)
                return
            }

            let lineRangeInString = NSRange(location: 0, length: (line as NSString).length)
            if let match = listMarkerRegex.firstMatch(in: line, options: [], range: lineRangeInString) {
                let markerRange = NSRange(
                    location: lineRange.location + match.range.location,
                    length: match.range.length
                )
                attributed.addAttributes(listMarkerAttributes(), range: markerRange)
            }
        }

        return codeRanges
    }

    private static func apply(
        regex: NSRegularExpression,
        to attributed: NSMutableAttributedString,
        in wholeRange: NSRange,
        excluding excludedRanges: [NSRange],
        attributes: [NSAttributedString.Key: Any]
    ) {
        let matches = regex.matches(in: attributed.string, options: [], range: wholeRange)
        for match in matches where intersectsExcludedRanges(match.range, excludedRanges) == false {
            attributed.addAttributes(attributes, range: match.range)
        }
    }

    private static func intersectsExcludedRanges(_ range: NSRange, _ excludedRanges: [NSRange]) -> Bool {
        excludedRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func headingLevel(for line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }
        guard hashes.isEmpty == false, hashes.count <= 6 else { return nil }
        let suffixIndex = line.index(line.startIndex, offsetBy: hashes.count)
        guard suffixIndex < line.endIndex, line[suffixIndex] == " " else { return nil }
        return hashes.count
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: MarkdownEditorPalette.baseUIFont,
            .foregroundColor: MarkdownEditorPalette.bodyUIColor,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    private static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let fontSize = max(16.5, 24.0 - (Double(level - 1) * 2.0))
        let fontWeight: UIFont.Weight = level == 1 ? .bold : .semibold
        let color = level == 1 ? MarkdownEditorPalette.headingOneUIColor : MarkdownEditorPalette.headingSecondaryUIColor
        let paragraphStyle = baseParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = level <= 2 ? 8 : 4
        paragraphStyle.paragraphSpacing = 4

        return [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeight),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func blockquoteAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = baseParagraphStyle()
        paragraphStyle.headIndent = 14
        paragraphStyle.firstLineHeadIndent = 0

        return [
            .font: UIFont.monospacedSystemFont(ofSize: 16.5, weight: .medium),
            .foregroundColor: MarkdownEditorPalette.quoteUIColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func listMarkerAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 16.5, weight: .semibold),
            .foregroundColor: MarkdownEditorPalette.listMarkerUIColor
        ]
    }

    private static func codeFenceAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 15.5, weight: .semibold),
            .foregroundColor: MarkdownEditorPalette.fenceUIColor,
            .backgroundColor: MarkdownEditorPalette.codeBackgroundUIColor,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    private static func codeBlockAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 15.5, weight: .regular),
            .foregroundColor: MarkdownEditorPalette.codeUIColor,
            .backgroundColor: MarkdownEditorPalette.codeBackgroundUIColor,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    private static func inlineCodeAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 15.5, weight: .semibold),
            .foregroundColor: MarkdownEditorPalette.codeUIColor,
            .backgroundColor: MarkdownEditorPalette.codeBackgroundUIColor
        ]
    }

    private static func linkAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 16.5, weight: .semibold),
            .foregroundColor: MarkdownEditorPalette.linkUIColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private static func strongAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 16.5, weight: .bold),
            .foregroundColor: MarkdownEditorPalette.emphasisUIColor
        ]
    }

    private static func emphasisAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.monospacedSystemFont(ofSize: 16.5, weight: .medium),
            .foregroundColor: MarkdownEditorPalette.emphasisUIColor
        ]
    }

    private static func baseParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.paragraphSpacing = 2
        return style
    }
}

private enum MarkdownEditorAIError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "模型返回了空文档，已取消本次修改。"
        }
    }
}

private struct PDFPreviewRepresentable: UIViewRepresentable {
    let attachment: ChatDocumentAttachment
    @Binding var currentPageIndex: Int
    @Binding var totalPageCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPageIndex: $currentPageIndex,
            totalPageCount: $totalPageCount
        )
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.965, alpha: 1)
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = UIEdgeInsets(top: 18, left: 0, bottom: 18, right: 0)

        if let document = PDFDocument(url: attachment.resolvedURL) {
            pdfView.document = document
            totalPageCount = document.pageCount
            currentPageIndex = 1
        }

        context.coordinator.attach(to: pdfView)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil, let document = PDFDocument(url: attachment.resolvedURL) {
            uiView.document = document
            totalPageCount = document.pageCount
            currentPageIndex = 1
        }
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        @Binding private var currentPageIndex: Int
        @Binding private var totalPageCount: Int
        private var observer: NSObjectProtocol?

        init(currentPageIndex: Binding<Int>, totalPageCount: Binding<Int>) {
            self._currentPageIndex = currentPageIndex
            self._totalPageCount = totalPageCount
        }

        func attach(to pdfView: PDFView) {
            detach()

            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak pdfView, weak self] _ in
                guard let self, let pdfView, let document = pdfView.document, let currentPage = pdfView.currentPage else {
                    return
                }

                self.totalPageCount = document.pageCount
                self.currentPageIndex = max(document.index(for: currentPage) + 1, 1)
            }
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }
    }
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
