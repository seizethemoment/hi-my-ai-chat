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
    @StateObject private var voiceInputController = VoiceInputController()
    @AppStorage("voice_auto_send_enabled") private var isVoiceAutoSendEnabled = true
    @AppStorage("markdown_agent_floating_bubble_x") private var floatingBubbleNormalizedX = 0.92
    @AppStorage("markdown_agent_floating_bubble_y") private var floatingBubbleNormalizedY = 0.82
    @State private var draft = ""
    @State private var savedDraft = ""
    @State private var aiInstruction = ""
    @State private var isEditing = false
    @State private var isApplyingAI = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isShareSheetPresented = false
    @State private var isAIDockExpanded = false
    @State private var agentScopeMode: MarkdownAgentScopeMode = .fullDocument
    @State private var lineRangeInput = ""
    @State private var selectionSnapshot = MarkdownEditorSelectionSnapshot.empty
    @State private var pendingProposal: MarkdownAgentPendingProposal?
    @State private var activityEntries: [MarkdownAgentActivityEntry] = []
    @State private var isActivityLogPresented = false
    @State private var canRollbackRevision = false
    @State private var redoSnapshots: [MarkdownAgentRevisionSnapshot] = []
    @State private var floatingBubbleDragOffset: CGSize = .zero
    @State private var isVoiceCancellationPending = false
    @State private var suppressRedoInvalidation = false

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

                        MarkdownSyntaxTextEditor(
                            text: $draft,
                            selectionSnapshot: $selectionSnapshot,
                            extraBottomInset: editorBottomInset
                        )
                            .allowsHitTesting(isApplyingAI == false)
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
            if isEditing, isAIDockExpanded {
                MarkdownEditorAIDockView(
                    instruction: $aiInstruction,
                    isExpanded: $isAIDockExpanded,
                    scopeMode: $agentScopeMode,
                    lineRangeInput: $lineRangeInput,
                    selectionSnapshot: selectionSnapshot,
                    totalLineCount: totalLineCount,
                    canApplyAI: canApplyAI,
                    isApplyingAI: isApplyingAI,
                    statusMessage: statusMessage,
                    isVoiceCapturing: voiceInputController.state != .idle,
                    isVoiceCaptureEnabled: isApplyingAI == false,
                    onVoicePressBegan: beginMarkdownVoiceCapture,
                    onVoiceCancelPreviewChanged: handleMarkdownVoiceCancellationPendingChange,
                    onVoicePressEnded: endMarkdownVoiceCapture,
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
        .overlay {
            if isEditing, isAIDockExpanded == false {
                GeometryReader { proxy in
                    let bubbleCenter = resolvedFloatingBubbleCenter(in: proxy.size)

                    MarkdownFloatingAssistantBubble(
                        showsIndicator: floatingBubbleShowsIndicator,
                        accessibilityValue: floatingBubbleAccessibilityValue
                    )
                    .position(bubbleCenter)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                floatingBubbleDragOffset = value.translation
                            }
                            .onEnded { value in
                                let baseCenter = persistedFloatingBubbleCenter(in: proxy.size)
                                let targetCenter = CGPoint(
                                    x: baseCenter.x + value.translation.width,
                                    y: baseCenter.y + value.translation.height
                                )
                                persistFloatingBubbleCenter(targetCenter, in: proxy.size)
                                floatingBubbleDragOffset = .zero
                            }
                    )
                    .onTapGesture {
                        floatingBubbleDragOffset = .zero
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isAIDockExpanded = true
                        }
                    }

                }
                .transition(.opacity)
            }
        }
        .overlay {
            if voiceInputController.state.showsOverlay {
                RecordingOverlayView(
                    state: voiceInputController.state,
                    transcript: voiceInputController.transcript,
                    sendMode: voiceSendMode,
                    isCancellationPending: isVoiceCancellationPending
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(3)
            }
        }
        .task {
            if draft.isEmpty {
                loadDraft()
            }
            updateRevisionAvailability()
        }
        .onChange(of: voiceInputController.finalTranscript) { _, transcript in
            guard let transcript else { return }
            applyVoiceTranscript(transcript)
            voiceInputController.consumeFinalTranscript()
        }
        .onChange(of: voiceInputController.lastErrorMessage) { _, errorMessage in
            guard let errorMessage else { return }
            self.errorMessage = errorMessage
            appendActivityLog(
                kind: .failure,
                title: "语音输入失败",
                detail: errorMessage
            )
            voiceInputController.consumeLastErrorMessage()
        }
        .onChange(of: voiceInputController.toastMessage) { _, message in
            guard let message else { return }
            statusMessage = message
            appendActivityLog(
                kind: .warning,
                title: "语音输入提示",
                detail: message
            )
            voiceInputController.consumeToastMessage()
        }
        .onChange(of: isEditing) { _, isEditing in
            guard isEditing == false else { return }
            cancelMarkdownVoiceCapture()
        }
        .onChange(of: draft) { oldValue, newValue in
            guard oldValue != newValue else { return }
            guard suppressRedoInvalidation == false else { return }
            if redoSnapshots.isEmpty == false {
                redoSnapshots.removeAll()
            }
        }
        .onDisappear {
            cancelMarkdownVoiceCapture()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheetView(activityItems: [attachment.resolvedURL])
        }
        .sheet(item: $pendingProposal) { proposal in
            MarkdownAgentProposalSheetView(
                pendingProposal: proposal,
                onApply: confirmPendingProposal,
                onDiscard: discardPendingProposal
            )
        }
        .sheet(isPresented: $isActivityLogPresented) {
            MarkdownAgentActivityLogSheetView(entries: activityEntries)
        }
        .alert(
            "操作不可用",
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

    private var voiceSendMode: VoiceSendMode {
        isVoiceAutoSendEnabled ? .auto : .manual
    }

    private var canRedoRevision: Bool {
        redoSnapshots.isEmpty == false
    }

    private var canApplyAI: Bool {
        canApplyAI(for: aiInstruction)
    }

    private func canApplyAI(for instruction: String) -> Bool {
        guard isApplyingAI == false,
              trimmedDraft.isEmpty == false,
              instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }

        switch agentScopeMode {
        case .fullDocument:
            return true
        case .selection:
            return selectionSnapshot.hasSelection
        case .lineRange:
            return (try? MarkdownLineLocator.parseLineRange(from: lineRangeInput, maxLine: totalLineCount)) != nil
        }
    }

    private var editorBottomInset: CGFloat {
        isAIDockExpanded ? 168 : 28
    }

    private var totalLineCount: Int {
        MarkdownLineLocator.lineCount(in: draft)
    }

    private var floatingBubbleShowsIndicator: Bool {
        if let statusMessage, statusMessage.isEmpty == false {
            return true
        }

        return aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var floatingBubbleAccessibilityValue: String {
        if let statusMessage, statusMessage.isEmpty == false {
            return statusMessage
        }

        let trimmedInstruction = aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInstruction.isEmpty == false {
            return "\(agentScopeMode.title)模式已就绪"
        }

        return "拖拽或点击展开 AI 修改文档"
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

            if isEditing == false {
                Button(action: { isShareSheetPresented = true }) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("markdown_document_share_button")
            }

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
                Button(action: { isActivityLogPresented = true }) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(activityEntries.isEmpty)
                .opacity(activityEntries.isEmpty ? 0.35 : 1)
                .accessibilityIdentifier("markdown_document_log_button")

                Button(action: rollbackLastRevision) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(canRollbackRevision == false || isApplyingAI)
                .opacity(canRollbackRevision && isApplyingAI == false ? 1 : 0.35)
                .accessibilityIdentifier("markdown_document_rollback_button")

                Button(action: redoLastRevision) {
                    Image(systemName: "arrow.uturn.forward.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(canRedoRevision == false || isApplyingAI)
                .opacity(canRedoRevision && isApplyingAI == false ? 1 : 0.35)
                .accessibilityIdentifier("markdown_document_redo_button")

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
            appendActivityLog(
                kind: .failure,
                title: "读取失败",
                detail: "无法从本地载入 Markdown 文件内容。"
            )
            return
        }

        draft = content
        savedDraft = content
        selectionSnapshot = .empty
        redoSnapshots.removeAll()
        appendActivityLog(
            kind: .info,
            title: "文档已加载",
            detail: "已载入 \(MarkdownLineLocator.lineCount(in: content)) 行 Markdown 内容。"
        )
    }

    private func saveDraft() {
        do {
            try ChatDocumentStore.updateMarkdownFile(for: attachment, content: draft)
            savedDraft = draft
            statusMessage = "已保存修改"
            appendActivityLog(
                kind: .success,
                title: "手动保存",
                detail: "已将当前编辑内容写回到本地 Markdown 文件。"
            )
        } catch {
            errorMessage = error.localizedDescription
            appendActivityLog(
                kind: .failure,
                title: "保存失败",
                detail: error.localizedDescription
            )
        }
    }

    private func dismissWithAutoSave() {
        cancelMarkdownVoiceCapture()
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
            errorMessage = MarkdownAgentError.emptyDocument.localizedDescription
            return
        }

        cancelMarkdownVoiceCapture()
        isAIDockExpanded = true
        isApplyingAI = true
        statusMessage = "Markdown agent 正在生成修改提案…"

        Task {
            do {
                let scope = try resolvedEditScope(for: sourceDraft)
                await MainActor.run {
                    appendActivityLog(
                        kind: .info,
                        title: "提案开始",
                        detail: "范围：\(scope.label)；指令：\(instruction)"
                    )
                }

                let service = try MarkdownDocumentAgentService()
                let proposal = try await service.proposeEdit(
                    fileName: attachment.fileName,
                    content: sourceDraft,
                    instruction: instruction,
                    scope: scope,
                    timeoutInterval: 90
                )
                let diff = MarkdownDiffEngine.makeDiff(
                    original: sourceDraft,
                    updated: proposal.updatedMarkdown
                )

                guard diff.hasChanges else {
                    throw MarkdownAgentError.unchangedProposal
                }

                await MainActor.run {
                    pendingProposal = MarkdownAgentPendingProposal(
                        instruction: instruction,
                        scope: scope,
                        originalMarkdown: sourceDraft,
                        proposal: proposal,
                        diff: diff
                    )
                    aiInstruction = ""
                    isApplyingAI = false
                    statusMessage = "提案已生成，请确认后写回"
                    appendActivityLog(
                        kind: .success,
                        title: "提案已生成",
                        detail: "\(proposal.summary)；\(diff.stats.summaryText)"
                    )
                }
            } catch {
                await MainActor.run {
                    isApplyingAI = false
                    statusMessage = nil
                    errorMessage = "Markdown agent 生成失败：\(error.localizedDescription)"
                    appendActivityLog(
                        kind: .failure,
                        title: "提案失败",
                        detail: error.localizedDescription
                    )
                }
            }
        }
    }

    private func resolvedEditScope(for content: String) throws -> MarkdownAgentEditScope {
        switch agentScopeMode {
        case .fullDocument:
            return .fullDocument(totalLines: MarkdownLineLocator.lineCount(in: content))
        case .selection:
            guard selectionSnapshot.hasSelection,
                  let lineRange = selectionSnapshot.lineRange else {
                throw MarkdownAgentError.missingSelection
            }
            return .selection(
                selectedText: selectionSnapshot.selectedText,
                lineRange: lineRange
            )
        case .lineRange:
            let lineRange = try MarkdownLineLocator.parseLineRange(
                from: lineRangeInput,
                maxLine: MarkdownLineLocator.lineCount(in: content)
            )
            return .lineRange(
                lineRange,
                excerpt: MarkdownLineLocator.excerpt(for: lineRange, in: content),
                totalLines: MarkdownLineLocator.lineCount(in: content)
            )
        }
    }

    private func confirmPendingProposal() {
        guard let pendingProposal else { return }

        do {
            redoSnapshots.removeAll()
            try MarkdownRevisionStore.push(
                snapshot: MarkdownAgentRevisionSnapshot(
                    fileName: attachment.fileName,
                    instruction: pendingProposal.instruction,
                    summary: pendingProposal.proposal.summary,
                    content: pendingProposal.originalMarkdown
                ),
                for: attachment
            )
            try ChatDocumentStore.updateMarkdownFile(
                for: attachment,
                content: pendingProposal.proposal.updatedMarkdown
            )

            applyProgrammaticDraftState(pendingProposal.proposal.updatedMarkdown)
            statusMessage = "提案已写回，可通过回滚按钮恢复"
            appendActivityLog(
                kind: .success,
                title: "提案已写回",
                detail: "\(pendingProposal.proposal.summary)；可随时回滚到上一个版本。"
            )
            AppLog.markdownAgent(
                "proposal_applied file=\(attachment.fileName) summary=\(pendingProposal.proposal.summary)"
            )
            self.pendingProposal = nil
            updateRevisionAvailability()
        } catch {
            errorMessage = error.localizedDescription
            appendActivityLog(
                kind: .failure,
                title: "写回失败",
                detail: error.localizedDescription
            )
        }
    }

    private func discardPendingProposal() {
        guard let pendingProposal else { return }
        appendActivityLog(
            kind: .warning,
            title: "提案已放弃",
            detail: "已放弃这次 AI 修改提案：\(pendingProposal.proposal.summary)"
        )
        self.pendingProposal = nil
        statusMessage = "已放弃这次提案"
    }

    private func rollbackLastRevision() {
        do {
            guard let snapshot = try MarkdownRevisionStore.popLatest(for: attachment) else {
                statusMessage = "当前没有可回滚的版本"
                return
            }

            redoSnapshots.append(
                MarkdownAgentRevisionSnapshot(
                    fileName: attachment.fileName,
                    instruction: "rollback",
                    summary: "回滚前版本",
                    content: draft
                )
            )

            try ChatDocumentStore.updateMarkdownFile(
                for: attachment,
                content: snapshot.content
            )

            applyProgrammaticDraftState(snapshot.content)
            statusMessage = "已回滚到上一版"
            appendActivityLog(
                kind: .success,
                title: "已回滚",
                detail: "已恢复到 \(snapshot.createdAt.formatted(date: .omitted, time: .standard)) 的版本。"
            )
            AppLog.markdownAgent(
                "rollback_applied file=\(attachment.fileName) snapshot=\(snapshot.id.uuidString)"
            )
            updateRevisionAvailability()
        } catch {
            errorMessage = error.localizedDescription
            appendActivityLog(
                kind: .failure,
                title: "回滚失败",
                detail: error.localizedDescription
            )
        }
    }

    private func redoLastRevision() {
        do {
            guard let snapshot = redoSnapshots.popLast() else {
                statusMessage = "当前没有可重做的版本"
                return
            }

            try MarkdownRevisionStore.push(
                snapshot: MarkdownAgentRevisionSnapshot(
                    fileName: attachment.fileName,
                    instruction: "redo",
                    summary: "重做前版本",
                    content: draft
                ),
                for: attachment
            )

            try ChatDocumentStore.updateMarkdownFile(
                for: attachment,
                content: snapshot.content
            )

            applyProgrammaticDraftState(snapshot.content)
            statusMessage = "已恢复到回滚前版本"
            appendActivityLog(
                kind: .success,
                title: "已重做",
                detail: "已恢复到刚才撤销前的版本。"
            )
            AppLog.markdownAgent(
                "redo_applied file=\(attachment.fileName) snapshot=\(snapshot.id.uuidString)"
            )
            updateRevisionAvailability()
        } catch {
            errorMessage = error.localizedDescription
            appendActivityLog(
                kind: .failure,
                title: "重做失败",
                detail: error.localizedDescription
            )
        }
    }

    private func updateRevisionAvailability() {
        canRollbackRevision = MarkdownRevisionStore.hasSnapshots(for: attachment)
    }

    private func applyProgrammaticDraftState(_ content: String) {
        suppressRedoInvalidation = true
        draft = content
        savedDraft = content
        selectionSnapshot = .empty

        Task { @MainActor in
            await Task.yield()
            suppressRedoInvalidation = false
        }
    }

    private func appendActivityLog(
        kind: MarkdownAgentActivityEntry.Kind,
        title: String,
        detail: String
    ) {
        let entry = MarkdownAgentActivityEntry(
            timestamp: Date(),
            kind: kind,
            title: title,
            detail: detail
        )
        activityEntries.append(entry)
        if activityEntries.count > 40 {
            activityEntries.removeFirst(activityEntries.count - 40)
        }
        AppLog.markdownAgent("\(title) detail=\(detail)")
    }

    private func beginMarkdownVoiceCapture() {
        guard isEditing, isApplyingAI == false else { return }
        isVoiceCancellationPending = false
        statusMessage = "请说出要如何修改这份 Markdown"
        voiceInputController.beginCapture()
        appendActivityLog(
            kind: .info,
            title: "语音输入开始",
            detail: "开始录制语音指令。"
        )
    }

    private func handleMarkdownVoiceCancellationPendingChange(_ isPending: Bool) {
        guard isEditing else { return }
        isVoiceCancellationPending = isPending
    }

    private func endMarkdownVoiceCapture(_ cancelled: Bool) {
        guard isEditing else { return }

        isVoiceCancellationPending = false
        if cancelled {
            voiceInputController.cancelCapture()
            statusMessage = "已取消这次语音输入"
            appendActivityLog(
                kind: .warning,
                title: "语音输入取消",
                detail: "用户取消了语音输入。"
            )
        } else {
            voiceInputController.endCapture()
            statusMessage = "正在整理语音内容…"
        }
    }

    private func cancelMarkdownVoiceCapture() {
        voiceInputController.cancelCapture()
        isVoiceCancellationPending = false
    }

    private func applyVoiceTranscript(_ transcript: String) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTranscript.isEmpty == false else { return }

        let updatedInstruction: String
        if aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedInstruction = trimmedTranscript
        } else {
            updatedInstruction = aiInstruction + "\n" + trimmedTranscript
        }
        aiInstruction = updatedInstruction

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isAIDockExpanded = true
        }
        appendActivityLog(
            kind: .success,
            title: "语音已转写",
            detail: "已将语音内容写入 AI 指令输入框。"
        )

        if voiceSendMode == .auto, canApplyAI(for: updatedInstruction) {
            statusMessage = "语音内容已写入，正在生成提案…"
            DispatchQueue.main.async {
                applyAIEdit()
            }
        } else if voiceSendMode == .auto {
            statusMessage = "语音内容已写入，请先确认范围后再生成提案"
        } else {
            statusMessage = "语音内容已写入，请确认后生成提案"
        }
    }

    private func resolvedFloatingBubbleCenter(in size: CGSize) -> CGPoint {
        let persistedCenter = persistedFloatingBubbleCenter(in: size)
        return clampedFloatingBubbleCenter(
            CGPoint(
                x: persistedCenter.x + floatingBubbleDragOffset.width,
                y: persistedCenter.y + floatingBubbleDragOffset.height
            ),
            in: size
        )
    }

    private func persistedFloatingBubbleCenter(in size: CGSize) -> CGPoint {
        let bounds = floatingBubbleBounds(in: size)
        let x = bounds.minX + CGFloat(floatingBubbleNormalizedX) * bounds.width
        let y = bounds.minY + CGFloat(floatingBubbleNormalizedY) * bounds.height
        return clampedFloatingBubbleCenter(CGPoint(x: x, y: y), in: size)
    }

    private func persistFloatingBubbleCenter(_ center: CGPoint, in size: CGSize) {
        let bounds = floatingBubbleBounds(in: size)
        let clampedCenter = clampedFloatingBubbleCenter(center, in: size)

        if bounds.width > 0 {
            floatingBubbleNormalizedX = min(max(Double((clampedCenter.x - bounds.minX) / bounds.width), 0), 1)
        }

        if bounds.height > 0 {
            floatingBubbleNormalizedY = min(max(Double((clampedCenter.y - bounds.minY) / bounds.height), 0), 1)
        }
    }

    private func clampedFloatingBubbleCenter(_ center: CGPoint, in size: CGSize) -> CGPoint {
        let bounds = floatingBubbleBounds(in: size)
        return CGPoint(
            x: min(max(center.x, bounds.minX), bounds.maxX),
            y: min(max(center.y, bounds.minY), bounds.maxY)
        )
    }

    private func floatingBubbleBounds(in size: CGSize) -> CGRect {
        let diameter: CGFloat = 58
        let horizontalPadding: CGFloat = 20
        let topPadding: CGFloat = 112
        let bottomPadding: CGFloat = 116

        let minX = horizontalPadding + diameter / 2
        let maxX = max(minX, size.width - horizontalPadding - diameter / 2)
        let minY = topPadding + diameter / 2
        let maxY = max(minY, size.height - bottomPadding - diameter / 2)

        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0)
        )
    }
}

private struct MarkdownEditorAIDockView: View {
    @Binding var instruction: String
    @Binding var isExpanded: Bool
    @Binding var scopeMode: MarkdownAgentScopeMode
    @Binding var lineRangeInput: String
    let selectionSnapshot: MarkdownEditorSelectionSnapshot
    let totalLineCount: Int
    let canApplyAI: Bool
    let isApplyingAI: Bool
    let statusMessage: String?
    let isVoiceCapturing: Bool
    let isVoiceCaptureEnabled: Bool
    let onVoicePressBegan: () -> Void
    let onVoiceCancelPreviewChanged: (Bool) -> Void
    let onVoicePressEnded: (Bool) -> Void
    let onApply: () -> Void

    var body: some View {
        expandedContainer
            .padding(.horizontal, 10)
            .padding(.top, 8)
    }

    private var expandedContainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            expandedContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: -2)
        )
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("AI 修改", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.58))

                Spacer(minLength: 8)

                dockToggleButton(
                    title: "收起",
                    systemImage: "chevron.down"
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isExpanded = false
                    }
                }
                .accessibilityIdentifier("markdown_document_ai_dock_collapse_button")
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.46))
            }

            MarkdownAgentScopePickerView(scopeMode: $scopeMode)

            scopeHint
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )

            HStack(spacing: 12) {
                TextField("告诉模型如何修改这份 Markdown…", text: $instruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .tint(Color.black.opacity(0.84))
                    .lineLimit(1...3)
                    .submitLabel(.return)
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

                MarkdownVoiceCaptureButton(
                    isCapturing: isVoiceCapturing,
                    isCaptureEnabled: isVoiceCaptureEnabled,
                    onPressBegan: onVoicePressBegan,
                    onCancelPreviewChanged: onVoiceCancelPreviewChanged,
                    onPressEnded: onVoicePressEnded
                )
                .accessibilityIdentifier("markdown_document_ai_voice_button")

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
    }

    @ViewBuilder
    private var scopeHint: some View {
        switch scopeMode {
        case .fullDocument:
            VStack(alignment: .leading, spacing: 4) {
                Text("全文模式")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                Text("模型会参考整份 Markdown，当前共 \(totalLineCount) 行。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.44))
            }
        case .selection:
            VStack(alignment: .leading, spacing: 4) {
                Text("选区模式")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                Text(selectionSnapshot.hasSelection ? "当前范围：\(selectionSnapshot.lineLabel)" : "请先在编辑器里选中文本，再发起 AI 修改。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selectionSnapshot.hasSelection ? Color.black.opacity(0.44) : Color(red: 0.76, green: 0.35, blue: 0.20))
                    .lineLimit(2)
            }
        case .lineRange:
            VStack(alignment: .leading, spacing: 8) {
                Text("行号模式")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))

                TextField("输入行号，如 12-18", text: $lineRangeInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .accessibilityIdentifier("markdown_document_ai_line_range_input")

                Text("当前文档共 \(totalLineCount) 行。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.44))
            }
        }
    }

    private func dockToggleButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.46))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MarkdownFloatingAssistantBubble: View {
    let showsIndicator: Bool
    let accessibilityValue: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.48, blue: 1.0),
                            Color(red: 0.14, green: 0.66, blue: 0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)

            Image(systemName: "sparkles")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if showsIndicator {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(Color(red: 1.0, green: 0.73, blue: 0.18))
                            .frame(width: 8, height: 8)
                    )
                    .offset(x: 4, y: -2)
            }
        }
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("展开 AI 修改文档")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("markdown_document_ai_dock_expand_button")
    }
}

private struct MarkdownVoiceCaptureButton: View {
    let isCapturing: Bool
    let isCaptureEnabled: Bool
    var diameter: CGFloat = 34
    var iconSize: CGFloat = 15
    var shadowRadius: CGFloat = 10
    var shadowYOffset: CGFloat = 5
    let onPressBegan: () -> Void
    let onCancelPreviewChanged: (Bool) -> Void
    let onPressEnded: (Bool) -> Void

    @State private var isPressing = false
    @State private var isCancellationPending = false

    private let cancelThreshold: CGFloat = -72

    var body: some View {
        Circle()
            .fill(backgroundFill)
            .overlay(
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: Color.black.opacity(0.12), radius: shadowRadius, x: 0, y: shadowYOffset)
            .opacity(isCaptureEnabled ? 1 : 0.45)
            .contentShape(Circle())
            .gesture(dragGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("按住语音输入")
            .accessibilityValue(isCapturing ? "正在录音" : "松开后会写入 AI 指令")
            .accessibilityAddTraits(.isButton)
    }

    private var backgroundFill: some ShapeStyle {
        LinearGradient(
            colors: isCapturing
                ? [
                    Color(red: 0.96, green: 0.31, blue: 0.35),
                    Color(red: 1.0, green: 0.47, blue: 0.38)
                ]
                : [
                    Color(red: 0.09, green: 0.48, blue: 1.0),
                    Color(red: 0.14, green: 0.66, blue: 0.96)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconName: String {
        if isCancellationPending {
            return "xmark"
        }

        return isCapturing ? "waveform" : "mic.fill"
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isCaptureEnabled else { return }

                if isPressing == false {
                    isPressing = true
                    onPressBegan()
                }

                let nextPending = value.translation.height <= cancelThreshold
                guard nextPending != isCancellationPending else { return }
                isCancellationPending = nextPending
                onCancelPreviewChanged(nextPending)
            }
            .onEnded { _ in
                let shouldCancel = isCancellationPending
                isPressing = false
                isCancellationPending = false
                onCancelPreviewChanged(false)
                if isCaptureEnabled {
                    onPressEnded(shouldCancel)
                }
            }
    }
}

private struct MarkdownSyntaxTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectionSnapshot: MarkdownEditorSelectionSnapshot
    var extraBottomInset: CGFloat = 0

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
        textView.textContainerInset = textContainerInset
        textView.textContainer.lineFragmentPadding = 0
        context.coordinator.applyHighlighting(to: textView, text: text, preserveSelection: false)
        context.coordinator.updateSelectionSnapshot(from: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        uiView.textContainerInset = textContainerInset
        context.coordinator.syncTextView(uiView)
    }

    private var textContainerInset: UIEdgeInsets {
        UIEdgeInsets(top: 18, left: 18, bottom: 28 + extraBottomInset, right: 18)
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
            guard isApplyingProgrammaticUpdate == false else { return }

            if parent.text != textView.text {
                parent.text = textView.text
            }

            guard textView.markedTextRange == nil else {
                needsHighlightRefreshAfterMarkedText = true
                return
            }

            applyHighlighting(to: textView, text: textView.text, preserveSelection: true)
            updateSelectionSnapshot(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard isApplyingProgrammaticUpdate == false else { return }
            updateSelectionSnapshot(from: textView)
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
            updateSelectionSnapshot(from: textView)
        }

        func updateSelectionSnapshot(from textView: UITextView) {
            let snapshot = MarkdownLineLocator.makeSelectionSnapshot(
                text: textView.text ?? "",
                selectedRange: textView.selectedRange
            )
            guard parent.selectionSnapshot != snapshot else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.parent.selectionSnapshot != snapshot else { return }
                self.parent.selectionSnapshot = snapshot
            }
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
