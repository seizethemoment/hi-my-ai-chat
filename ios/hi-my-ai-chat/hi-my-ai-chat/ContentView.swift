//
//  ContentView.swift
//  hi-my-ai-chat
//
//  Created by 李俊鹏 on 2026/4/17.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    private enum DemoStreamStep {
        case pause(UInt64)
        case text(String)
        case tool(ChatToolCall)
    }

    @StateObject private var sessionStore = ChatSessionStore()
    @StateObject private var voiceInputController = VoiceInputController()
    @StateObject private var voicePlaybackController = VoicePlaybackController()
    @AppStorage("voice_auto_send_enabled") private var isVoiceAutoSendEnabled = true
    @AppStorage(OpenAISettings.apiKeyStorageKey) private var openAIAPIKey = ""
    @AppStorage(OpenAISettings.baseURLStorageKey) private var openAIBaseURL = ""
    @AppStorage(OpenAISettings.modelStorageKey) private var openAIModel = ""
    @State private var selectedSidebarItem: SidebarItem? = .chat
    @State private var isSidebarPresented = false
    @State private var sidebarRevealWidth: CGFloat = 0
    @State private var currentSessionID: UUID?
    @State private var isSidebarEditingSessions = false
    @State private var isSidebarSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var isSidebarDrawerMounted = false
    @State private var recentSearchTerms = SidebarSearchHistoryStore.load()
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var pendingImageAttachments: [ChatImageAttachment] = []
    @State private var pendingDocumentAttachments: [ChatDocumentAttachment] = []
    @State private var isDocumentPickerPresented = false
    @State private var selectedDocumentPreview: ChatDocumentAttachment?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isRenameSessionAlertPresented = false
    @State private var renameSessionDraft = ""
    @State private var isRequestingReply = false
    @State private var currentRetryAttempt = 0
    @State private var isAttachmentDrawerPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isVoiceCancellationPending = false
    @State private var voiceInputAlertMessage: String?
    @State private var toastMessage: String?
    @State private var mediaAlertMessage: String?
    @State private var prefersTextInput = false
    @State private var replyTasks: [UUID: Task<Void, Never>] = [:]
    @State private var liveMessagesBySession: [UUID: [ChatMessage]] = [:]
    @State private var retryAttemptsBySession: [UUID: Int] = [:]
    @State private var activeAssistantMessageIDsBySession: [UUID: UUID] = [:]
    @State private var activeAssistantMessageID: UUID?
    @State private var scrollToBottomRequest = 0
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var sidebarUnmountTask: Task<Void, Never>?
    @FocusState private var isTextFieldFocused: Bool
    private let makeChatService: (OpenAIModelConfiguration) throws -> any ChatServiceProtocol
    private let conversationContextBuilder = ConversationContextBuilder()

    private let quickActions = [
        QuickAction(
            id: "rich_streaming_demo",
            title: "流式渲染验收",
            systemImage: "sparkles.rectangle.stack",
            scenario: .richStreaming,
            accessibilityIdentifier: "quick_action_rich_streaming_demo"
        ),
        QuickAction(
            id: "tool_failure_demo",
            title: "失败态验收",
            systemImage: "exclamationmark.triangle",
            scenario: .toolFailure,
            accessibilityIdentifier: "quick_action_tool_failure_demo"
        ),
        QuickAction(
            id: "season_poem",
            title: "写一首关于季节的古诗",
            systemImage: "leaf",
            prompt: "写一首关于季节的古诗",
            accessibilityIdentifier: "quick_action_season_poem"
        ),
        QuickAction(
            id: "tell_joke",
            title: "讲一个笑话给我听",
            systemImage: "face.smiling",
            prompt: "讲一个笑话给我听",
            accessibilityIdentifier: "quick_action_tell_joke"
        )
    ]

    private let imageQuickActions = [
        QuickAction(
            id: "describe_image",
            title: "这是什么",
            systemImage: "questionmark.circle",
            prompt: "这是什么？",
            accessibilityIdentifier: "quick_action_describe_image"
        ),
        QuickAction(
            id: "image_caption",
            title: "图片配文",
            systemImage: "text.quote",
            prompt: "帮我为这张图片写一段配文。",
            accessibilityIdentifier: "quick_action_image_caption"
        ),
        QuickAction(
            id: "extract_text",
            title: "提取图中文字",
            systemImage: "text.viewfinder",
            prompt: "请提取这张图片里的所有文字。",
            accessibilityIdentifier: "quick_action_extract_text"
        ),
        QuickAction(
            id: "translate_text",
            title: "翻译图中文字",
            systemImage: "globe",
            prompt: "请识别并翻译这张图片里的文字。",
            accessibilityIdentifier: "quick_action_translate_text"
        )
    ]

    private let markdownDocumentQuickActions = [
        QuickAction(
            id: "edit_markdown_document",
            title: "继续编辑文档",
            systemImage: "square.and.pencil",
            prompt: "请先阅读我上传的 Markdown 文档，并按我的后续要求继续编辑它。",
            accessibilityIdentifier: "quick_action_edit_markdown_document"
        ),
        QuickAction(
            id: "summarize_markdown_document",
            title: "详细总结文档内容",
            systemImage: "text.alignleft",
            prompt: "请详细总结这份 Markdown 文档的结构、重点和待完善之处。",
            accessibilityIdentifier: "quick_action_summarize_markdown_document"
        ),
        QuickAction(
            id: "short_summary_markdown_document",
            title: "生成简短摘要",
            systemImage: "arrow.right",
            prompt: "请为这份 Markdown 文档生成一段简短摘要。",
            accessibilityIdentifier: "quick_action_short_summary_markdown_document"
        )
    ]

    private let pdfDocumentQuickActions = [
        QuickAction(
            id: "podcast_pdf_document",
            title: "听播客",
            systemImage: "waveform",
            prompt: "请把这份 PDF 文档改写成适合 5 分钟收听的中文播客讲稿。",
            accessibilityIdentifier: "quick_action_podcast_pdf_document"
        ),
        QuickAction(
            id: "summarize_pdf_document",
            title: "详细总结文档内容",
            systemImage: "text.alignleft",
            prompt: "请详细总结这份 PDF 文档的核心内容、结构和重点。",
            accessibilityIdentifier: "quick_action_summarize_pdf_document"
        ),
        QuickAction(
            id: "short_summary_pdf_document",
            title: "生成简短摘要",
            systemImage: "arrow.right",
            prompt: "请为这份 PDF 文档生成一段简短摘要。",
            accessibilityIdentifier: "quick_action_short_summary_pdf_document"
        )
    ]

    private let attachmentActions = [
        AttachmentAction(
            title: "相机",
            systemImage: "camera.fill",
            accessibilityIdentifier: "attachment_camera_button",
            source: .camera
        ),
        AttachmentAction(
            title: "相册",
            systemImage: "photo.fill.on.rectangle.fill",
            accessibilityIdentifier: "attachment_photo_library_button",
            source: .photoLibrary
        ),
        AttachmentAction(
            title: "文件",
            systemImage: "doc.fill",
            accessibilityIdentifier: "attachment_files_button",
            source: .files
        )
    ]

    init(
        makeChatService: @escaping (OpenAIModelConfiguration) throws -> any ChatServiceProtocol = { configuration in
            try OpenAIChatService(configuration: configuration)
        }
    ) {
        self.makeChatService = makeChatService
    }

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPendingAttachments: Bool {
        pendingImageAttachments.isEmpty == false || pendingDocumentAttachments.isEmpty == false
    }

    private var canSend: Bool {
        (trimmedInput.isEmpty == false || hasPendingAttachments) && isRequestingReply == false
    }

    private var isTextMode: Bool {
        prefersTextInput || inputText.isEmpty == false || hasPendingAttachments
    }

    private var activeQuickActions: [QuickAction] {
        if let firstDocument = pendingDocumentAttachments.first {
            switch firstDocument.kind {
            case .markdown:
                return markdownDocumentQuickActions
            case .pdf, .other:
                return pdfDocumentQuickActions
            }
        }

        return pendingImageAttachments.isEmpty == false ? imageQuickActions : quickActions
    }

    private var voiceSendMode: VoiceSendMode {
        isVoiceAutoSendEnabled ? .auto : .manual
    }

    private var isVoiceOverlayVisible: Bool {
        voiceInputController.state.showsOverlay
    }

    private var topSubtitleText: String {
        if isRequestingReply {
            return currentRetryAttempt > 0 ? "连接较慢，正在重试..." : "正在生成回复..."
        }

        return "内容由 AI 生成"
    }

    private var currentSession: ChatSession? {
        if let currentSessionID {
            return sessionStore.session(for: currentSessionID) ?? sessionStore.selectedSession
        }

        return sessionStore.selectedSession
    }

    private var currentSessionTitle: String {
        currentSession?.title ?? ChatSession.defaultTitle
    }

    private var activeSidebarItem: SidebarItem {
        selectedSidebarItem ?? .chat
    }

    private var latestPlayableAssistantMessage: ChatMessage? {
        messages.last(where: isPlayableAssistantMessage(_:))
    }

    private var sidebarAnimation: Animation {
        .spring(response: 0.30, dampingFraction: 0.88)
    }

    private var favoriteEntries: [FavoritedMessageEntry] {
        sessionStore.sessions
            .flatMap { session in
                let sessionMessages = messages(for: session.id, fallback: session.messages)
                return sessionMessages.compactMap { message -> FavoritedMessageEntry? in
                    guard message.role == .assistant,
                          message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                          message.favoritedAt != nil else {
                        return nil
                    }

                    return FavoritedMessageEntry(
                        sessionID: session.id,
                        sessionTitle: session.title,
                        message: message
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.favoritedAt == rhs.favoritedAt {
                    return lhs.sessionTitle.localizedStandardCompare(rhs.sessionTitle) == .orderedAscending
                }

                return lhs.favoritedAt > rhs.favoritedAt
            }
    }

    private var favoritesSubtitleText: String {
        favoriteEntries.isEmpty ? "还没有收藏的回复" : "已收藏 \(favoriteEntries.count) 条回复"
    }

    private var composerLoadingText: String {
        currentRetryAttempt > 0 ? "重试中" : "生成中"
    }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = sidebarWidth(for: proxy.size.width)
            let drawerOffset = sidebarOffset(drawerWidth: drawerWidth)
            let revealedWidth = sidebarRevealedWidth(drawerWidth: drawerWidth)
            let revealProgress = min(max(revealedWidth / drawerWidth, 0), 1)
            let isSidebarInteractable = revealProgress > 0.001
            let showsSidebarDrawer = isSidebarDrawerMounted || isSidebarPresented || revealedWidth > 0.001

            ZStack(alignment: .leading) {
                detailView
                    .offset(x: revealedWidth)
                    .simultaneousGesture(sidebarOpenGesture(drawerWidth: drawerWidth), including: .all)
                    .zIndex(isSidebarPresented ? 1 : 3)

                if revealProgress > 0.001 {
                    Color.black.opacity(0.18 * revealProgress)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: closeSidebar)
                        .simultaneousGesture(sidebarCloseGesture(drawerWidth: drawerWidth))
                        .allowsHitTesting(revealProgress > 0.001)
                        .accessibilityIdentifier("sidebar_scrim")
                        .zIndex(2)
                }

                if showsSidebarDrawer {
                    sidebarDrawer(
                        drawerWidth: drawerWidth,
                        drawerOffset: drawerOffset,
                        revealProgress: revealProgress,
                        topInset: resolvedSidebarTopInset(proxy.safeAreaInsets.top),
                        bottomInset: resolvedSidebarBottomInset(proxy.safeAreaInsets.bottom),
                        isInteractable: isSidebarInteractable
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $isSidebarSearchPresented) {
            SidebarSearchView(
                sessions: sessionStore.filteredSessions(matching: ""),
                recentSearchTerms: recentSearchTerms,
                onDismiss: closeSidebarSearch,
                onRemoveRecentSearch: removeRecentSearch,
                onSelectRecentSearch: recordRecentSearch,
                onSelectSession: handleSearchSessionSelection
            )
        }
        .fullScreenCover(isPresented: $isSettingsPresented) {
            SettingsView(
                isVoiceAutoSendEnabled: $isVoiceAutoSendEnabled,
                openAIAPIKey: $openAIAPIKey,
                openAIBaseURL: $openAIBaseURL,
                openAIModel: $openAIModel,
                onDismiss: closeSettings
            )
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPickerView(
                onImagePicked: appendCapturedImage,
                onDismiss: dismissCamera
            )
        }
        .fullScreenCover(item: $selectedDocumentPreview) { attachment in
            ChatDocumentPreviewScreen(
                attachment: attachment,
                makeChatService: {
                    let configuration = OpenAIModelConfiguration(
                        apiKey: openAIAPIKey,
                        baseURL: openAIBaseURL,
                        model: openAIModel
                    )
                    return try makeChatService(configuration)
                }
            )
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 6,
            matching: .images,
            photoLibrary: .shared()
        )
        .fileImporter(
            isPresented: $isDocumentPickerPresented,
            allowedContentTypes: [.pdf, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: true
        ) { result in
            handlePickedDocuments(result)
        }
        .task(id: selectedPhotoItems.count) {
            let items = selectedPhotoItems
            guard items.isEmpty == false else { return }

            await appendSelectedPhotoItems(items)
            selectedPhotoItems = []
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch activeSidebarItem {
        case .chat:
            chatDetailView
        case .favorites:
            favoritesDetailView
        }
    }

    @ViewBuilder
    private func sidebarDrawer(
        drawerWidth: CGFloat,
        drawerOffset: CGFloat,
        revealProgress: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        isInteractable: Bool
    ) -> some View {
        let drawer = SidebarDrawerView(
            selectedItem: $selectedSidebarItem,
            selectedSessionID: currentSessionID,
            sessions: sessionStore.filteredSessions(matching: ""),
            isEditingSessions: isSidebarEditingSessions,
            revealProgress: revealProgress,
            topInset: topInset,
            bottomInset: bottomInset,
            onSearchTap: openSidebarSearch,
            onEditTap: toggleSidebarEditing,
            onSettingsTap: openSettings,
            onItemTap: closeSidebar,
            onSessionTap: handleSessionSelection,
            onDeleteSessionTap: handleSessionDeletion,
            onNewChatTap: createNewChatSession
        )
        .frame(width: drawerWidth)
        .frame(maxHeight: .infinity)
        .offset(x: drawerOffset)
        .ignoresSafeArea(edges: [.top, .bottom])
        .contentShape(Rectangle())
        .allowsHitTesting(isInteractable)
        .accessibilityHidden(isInteractable == false)
        .zIndex(isInteractable ? 4 : 0)

        if isInteractable {
            drawer
                .highPriorityGesture(sidebarCloseGesture(drawerWidth: drawerWidth), including: .all)
        } else {
            drawer
        }
    }

    private var chatDetailView: some View {
        ZStack(alignment: .bottom) {
            HomeBackgroundView()

            VStack(spacing: 0) {
                TopBarView(
                    title: currentSessionTitle,
                    subtitle: topSubtitleText,
                    onMenuTap: toggleSidebar,
                    onTitleTap: promptRenameCurrentSession,
                    isTitleEnabled: true,
                    isAudioAvailable: latestPlayableAssistantMessage != nil,
                    isAudioPlaying: latestPlayableAssistantMessage?.id == voicePlaybackController.playingMessageID,
                    onAudioTap: playLatestAssistantReply
                )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                ChatMessagesView(
                    messages: messages,
                    scrollToBottomRequest: scrollToBottomRequest,
                    canDeleteMessages: isRequestingReply == false,
                    playingMessageID: voicePlaybackController.playingMessageID,
                    onDeleteMessage: deleteMessage,
                    onUserCopyTap: handleUserMessageCopy,
                    onAssistantCopyTap: handleAssistantMessageCopy,
                    onAssistantAudioTap: toggleAssistantMessageAudio,
                    onAssistantFavoriteTap: toggleAssistantMessageFavorite,
                    onDocumentTap: openPreview
                ) {
                    dismissTransientUI()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    if let toastMessage {
                        InlineToastView(message: toastMessage)
                            .padding(.horizontal, 18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    ComposerDockView(
                        text: $inputText,
                        isAttachmentDrawerPresented: $isAttachmentDrawerPresented,
                        isTextFieldFocused: $isTextFieldFocused,
                        isTextMode: isTextMode,
                        canSend: canSend,
                        isRequestingReply: isRequestingReply,
                        loadingText: composerLoadingText,
                        quickActions: activeQuickActions,
                        attachmentActions: attachmentActions,
                        pendingAttachments: pendingImageAttachments,
                        pendingDocumentAttachments: pendingDocumentAttachments,
                        onQuickActionTap: applyQuickAction,
                        onPrimaryAttachmentTap: presentCamera,
                        onModeButtonTap: handleModeButtonTap,
                        onAttachmentTap: toggleAttachmentDrawer,
                        onAttachmentActionTap: handleAttachmentAction,
                        onRemovePendingAttachment: removePendingAttachment,
                        onRemovePendingDocument: removePendingDocument,
                        onPendingDocumentTap: openPreview,
                        onAddDocumentTap: presentDocumentPicker,
                        onVoicePressBegan: beginVoiceCapture,
                        onVoiceCancelPreviewChanged: handleVoiceCancellationPendingChange,
                        onVoicePressEnded: endVoiceCapture,
                        onSend: handleSend
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .animation(.easeInOut(duration: 0.18), value: toastMessage)
            }

            if isVoiceOverlayVisible {
                RecordingOverlayView(
                    state: voiceInputController.state,
                    transcript: voiceInputController.transcript,
                    sendMode: voiceSendMode,
                    isCancellationPending: isVoiceCancellationPending
                )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
            }
        }
        .background(Color(red: 0.985, green: 0.985, blue: 0.982))
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isAttachmentDrawerPresented)
        .animation(.easeInOut(duration: 0.18), value: isVoiceOverlayVisible)
        .task {
            initializeCurrentSessionIfNeeded()
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isAttachmentDrawerPresented = false
                }
            }
        }
        .onChange(of: voiceInputController.finalTranscript) { _, transcript in
            guard let transcript else { return }
            applyVoiceTranscript(transcript)
            voiceInputController.consumeFinalTranscript()
        }
        .onChange(of: voiceInputController.lastErrorMessage) { _, errorMessage in
            guard let errorMessage else { return }
            voiceInputAlertMessage = errorMessage
            voiceInputController.consumeLastErrorMessage()
        }
        .onChange(of: voiceInputController.toastMessage) { _, message in
            guard let message else { return }
            presentToast(message)
            voiceInputController.consumeToastMessage()
        }
        .alert(
            "语音输入不可用",
            isPresented: Binding(
                get: { voiceInputAlertMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        voiceInputAlertMessage = nil
                    }
                }
            ),
            actions: {
                Button("知道了", role: .cancel) {}
            },
            message: {
                Text(voiceInputAlertMessage ?? "")
            }
        )
        .alert(
            "图片不可用",
            isPresented: Binding(
                get: { mediaAlertMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        mediaAlertMessage = nil
                    }
                }
            ),
            actions: {
                Button("知道了", role: .cancel) {}
            },
            message: {
                Text(mediaAlertMessage ?? "")
            }
        )
        .alert(
            "修改会话名称",
            isPresented: $isRenameSessionAlertPresented,
            actions: {
                TextField("输入会话名称", text: $renameSessionDraft)

                Button("取消", role: .cancel) {
                    renameSessionDraft = ""
                }

                Button("保存") {
                    applySessionTitleEdit()
                }
            },
            message: {
                Text("留空会恢复为自动标题。")
            }
        )
    }

    private var favoritesDetailView: some View {
        ZStack(alignment: .bottom) {
            HomeBackgroundView()

            VStack(spacing: 0) {
                TopBarView(
                    title: SidebarItem.favorites.title,
                    subtitle: favoritesSubtitleText,
                    onMenuTap: toggleSidebar,
                    onTitleTap: {},
                    isTitleEnabled: false,
                    isAudioAvailable: false,
                    isAudioPlaying: false,
                    onAudioTap: {}
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

                FavoritesView(
                    entries: favoriteEntries,
                    onOpenEntry: openFavoritedMessage,
                    onRemoveFavorite: removeFavorite
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    if let toastMessage {
                        InlineToastView(message: toastMessage)
                            .padding(.horizontal, 18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.18), value: toastMessage)
            }
        }
        .background(Color(red: 0.985, green: 0.985, blue: 0.982))
    }

    private func toggleSidebar() {
        isSidebarPresented ? closeSidebar() : openSidebar()
    }

    private func openSidebar() {
        sidebarUnmountTask?.cancel()
        isSidebarDrawerMounted = true
        isAttachmentDrawerPresented = false
        isTextFieldFocused = false
        voiceInputController.cancelCapture()
        dismissKeyboard()

        withAnimation(sidebarAnimation) {
            isSidebarPresented = true
            sidebarRevealWidth = currentSidebarDrawerWidth()
        }
    }

    private func closeSidebar() {
        withAnimation(sidebarAnimation) {
            isSidebarPresented = false
            sidebarRevealWidth = 0
        }
        scheduleSidebarUnmount()
    }

    private func openSidebarSearch() {
        closeSidebar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isSidebarSearchPresented = true
        }
    }

    private func closeSidebarSearch() {
        isSidebarSearchPresented = false
    }

    private func openSettings() {
        closeSidebar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isSettingsPresented = true
        }
    }

    private func closeSettings() {
        isSettingsPresented = false
    }

    private func toggleSidebarEditing() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            isSidebarEditingSessions.toggle()
        }
    }

    private func initializeCurrentSessionIfNeeded() {
        guard currentSessionID == nil else { return }

        if let session = sessionStore.selectedSession {
            loadSession(session)
        } else {
            let session = sessionStore.createSession(select: true)
            loadSession(session)
        }
    }

    private func createNewChatSession() {
        selectedSidebarItem = .chat
        isSidebarEditingSessions = false

        if let reusableSession = sessionStore.reusableEmptySession() {
            if currentSessionID == reusableSession.id {
                loadSession(reusableSession)
            } else if let selectedSession = sessionStore.selectSession(id: reusableSession.id) {
                loadSession(selectedSession)
            }
            closeSidebar()
            return
        }

        let newSession = sessionStore.createSession(select: true)
        loadSession(newSession)
        closeSidebar()
    }

    private func handleSessionSelection(_ session: ChatSession) {
        selectedSidebarItem = .chat
        isSidebarEditingSessions = false

        guard currentSessionID != session.id else {
            closeSidebar()
            return
        }

        if let selectedSession = sessionStore.selectSession(id: session.id) {
            loadSession(selectedSession)
        }

        closeSidebar()
    }

    private func handleSearchSessionSelection(_ session: ChatSession, query: String) {
        recentSearchTerms = SidebarSearchHistoryStore.record(query)
        selectedSidebarItem = .chat
        if let selectedSession = sessionStore.selectSession(id: session.id) {
            loadSession(selectedSession)
        }
        isSidebarEditingSessions = false
        closeSidebarSearch()
    }

    private func handleSessionDeletion(_ session: ChatSession) {
        cancelReply(for: session.id)
        let nextSession = sessionStore.deleteSession(id: session.id)

        if currentSessionID == session.id, let nextSession {
            loadSession(nextSession)
        }
    }

    private func recordRecentSearch(_ term: String) {
        recentSearchTerms = SidebarSearchHistoryStore.record(term)
    }

    private func removeRecentSearch(_ term: String) {
        recentSearchTerms = SidebarSearchHistoryStore.remove(term)
    }

    private func deleteMessage(_ message: ChatMessage) {
        guard let currentSessionID, isRequestingReply == false else { return }

        var updatedMessages = messages(for: currentSessionID)
        guard let index = updatedMessages.firstIndex(where: { $0.id == message.id }) else { return }

        if voicePlaybackController.playingMessageID == message.id {
            voicePlaybackController.stop()
        }

        updatedMessages.remove(at: index)
        messages = updatedMessages
        liveMessagesBySession.removeValue(forKey: currentSessionID)
        sessionStore.updateMessages(updatedMessages, for: currentSessionID)
    }

    private func openPreview(_ attachment: ChatDocumentAttachment) {
        selectedDocumentPreview = attachment
    }

    private func loadSession(_ session: ChatSession) {
        voiceInputController.cancelCapture()
        voicePlaybackController.stop()
        toastDismissTask?.cancel()
        sidebarUnmountTask?.cancel()
        let sessionMessages = messages(for: session.id, fallback: session.messages)
        currentSessionID = session.id
        messages = sessionMessages
        inputText = ""
        pendingImageAttachments = []
        pendingDocumentAttachments = []
        selectedDocumentPreview = nil
        selectedPhotoItems = []
        isVoiceCancellationPending = false
        toastMessage = nil
        mediaAlertMessage = nil
        renameSessionDraft = ""
        isRenameSessionAlertPresented = false
        isAttachmentDrawerPresented = false
        isPhotoPickerPresented = false
        isDocumentPickerPresented = false
        isCameraPresented = false
        isTextFieldFocused = false
        prefersTextInput = false
        syncReplyState(for: session.id)
        dismissKeyboard()
    }

    private func scheduleSidebarUnmount() {
        sidebarUnmountTask?.cancel()

        guard isSidebarPresented == false else { return }

        sidebarUnmountTask = Task {
            try? await Task.sleep(nanoseconds: 360_000_000)
            await MainActor.run {
                guard isSidebarPresented == false, sidebarRevealWidth <= 0.001 else { return }
                isSidebarDrawerMounted = false
            }
        }
    }

    private func persistCurrentSession() {
        guard let currentSessionID else { return }
        sessionStore.updateMessages(messages, for: currentSessionID)
    }

    private func promptRenameCurrentSession() {
        guard let currentSession else { return }

        renameSessionDraft = currentSession.customTitle ?? currentSession.title
        isRenameSessionAlertPresented = true
    }

    private func applySessionTitleEdit() {
        guard let currentSessionID else { return }

        sessionStore.renameSession(id: currentSessionID, customTitle: renameSessionDraft)
        renameSessionDraft = ""
    }

    private func presentToast(_ message: String) {
        toastDismissTask?.cancel()

        withAnimation(.easeInOut(duration: 0.18)) {
            toastMessage = message
        }

        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    toastMessage = nil
                }
            }
        }
    }

    private func cancelReply(for sessionID: UUID) {
        replyTasks[sessionID]?.cancel()
        replyTasks.removeValue(forKey: sessionID)
        liveMessagesBySession.removeValue(forKey: sessionID)
        retryAttemptsBySession.removeValue(forKey: sessionID)
        activeAssistantMessageIDsBySession.removeValue(forKey: sessionID)

        if currentSessionID == sessionID {
            syncReplyState(for: sessionID)
        }
    }

    private func messages(for sessionID: UUID, fallback: [ChatMessage] = []) -> [ChatMessage] {
        if let liveMessages = liveMessagesBySession[sessionID] {
            return liveMessages
        }

        return sessionStore.session(for: sessionID)?.messages ?? fallback
    }

    private func updateMessages(_ updatedMessages: [ChatMessage], for sessionID: UUID) {
        liveMessagesBySession[sessionID] = updatedMessages

        if currentSessionID == sessionID {
            messages = updatedMessages
        }
    }

    private func persistMessages(
        _ updatedMessages: [ChatMessage],
        for sessionID: UUID,
        shouldRefreshTimestamp: Bool
    ) {
        updateMessages(updatedMessages, for: sessionID)
        sessionStore.updateMessages(
            updatedMessages,
            for: sessionID,
            shouldRefreshTimestamp: shouldRefreshTimestamp
        )
    }

    private func finishLiveMessages(_ finalMessages: [ChatMessage], for sessionID: UUID) {
        if currentSessionID == sessionID {
            messages = finalMessages
        }

        liveMessagesBySession.removeValue(forKey: sessionID)
        sessionStore.updateMessages(finalMessages, for: sessionID)
    }

    private func syncReplyState(for sessionID: UUID) {
        isRequestingReply = activeAssistantMessageIDsBySession[sessionID] != nil
        currentRetryAttempt = retryAttemptsBySession[sessionID] ?? 0
        activeAssistantMessageID = activeAssistantMessageIDsBySession[sessionID]
    }

    private func resolvedSidebarTopInset(_ proxyTopInset: CGFloat) -> CGFloat {
        max(proxyTopInset, currentWindowSafeAreaInsets().top)
    }

    private func resolvedSidebarBottomInset(_ proxyBottomInset: CGFloat) -> CGFloat {
        max(proxyBottomInset, currentWindowSafeAreaInsets().bottom)
    }

    private func currentWindowSafeAreaInsets() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private func sidebarWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.80, 282), 320)
    }

    private func currentSidebarDrawerWidth() -> CGFloat {
        let windowWidth = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds.width ?? UIScreen.main.bounds.width

        return sidebarWidth(for: windowWidth)
    }

    private func sidebarOffset(drawerWidth: CGFloat) -> CGFloat {
        sidebarRevealedWidth(drawerWidth: drawerWidth) - drawerWidth
    }

    private func sidebarRevealedWidth(drawerWidth: CGFloat) -> CGFloat {
        min(max(sidebarRevealWidth, 0), drawerWidth)
    }

    private func sidebarOpenGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard isSidebarPresented == false else { return }
                guard value.startLocation.x <= 44 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard value.translation.width > 0 else { return }
                if isSidebarDrawerMounted == false {
                    sidebarUnmountTask?.cancel()
                    isSidebarDrawerMounted = true
                }
                sidebarRevealWidth = min(drawerWidth, max(0, value.translation.width))
            }
            .onEnded { value in
                guard isSidebarPresented == false else { return }
                guard value.startLocation.x <= 44 else {
                    sidebarRevealWidth = 0
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    sidebarRevealWidth = 0
                    return
                }
                let shouldOpen = value.translation.width > drawerWidth * 0.22
                    || value.predictedEndTranslation.width > drawerWidth * 0.34

                if shouldOpen {
                    openSidebar()
                } else {
                    closeSidebar()
                }
            }
    }

    private func sidebarCloseGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard isSidebarPresented else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                sidebarRevealWidth = min(drawerWidth, max(0, drawerWidth + value.translation.width))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(sidebarAnimation) {
                        sidebarRevealWidth = drawerWidth
                    }
                    return
                }

                let shouldClose = value.translation.width < -drawerWidth * 0.22
                    || value.predictedEndTranslation.width < -drawerWidth * 0.34

                if shouldClose {
                    closeSidebar()
                } else {
                    withAnimation(sidebarAnimation) {
                        isSidebarPresented = true
                        sidebarRevealWidth = drawerWidth
                    }
                }
            }
    }

    private func applyQuickAction(_ action: QuickAction) {
        if let scenario = action.scenario {
            runDemoScenario(scenario)
            return
        }

        guard let prompt = action.prompt else { return }
        inputText = prompt
        prefersTextInput = true
        isAttachmentDrawerPresented = false
        focusComposerTextField()
    }

    private func handleAttachmentAction(_ action: AttachmentAction) {
        switch action.source {
        case .camera:
            presentCamera()
        case .photoLibrary:
            presentPhotoLibrary()
        case .files:
            presentDocumentPicker()
        }
    }

    private func presentPhotoLibrary() {
        voiceInputController.cancelCapture()
        isAttachmentDrawerPresented = false
        isTextFieldFocused = false
        dismissKeyboard()
        isPhotoPickerPresented = true
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            mediaAlertMessage = "当前设备不支持拍照，请在真机上使用相机功能。"
            return
        }

        voiceInputController.cancelCapture()
        isAttachmentDrawerPresented = false
        isTextFieldFocused = false
        dismissKeyboard()
        isCameraPresented = true
    }

    private func presentDocumentPicker() {
        voiceInputController.cancelCapture()
        isAttachmentDrawerPresented = false
        isTextFieldFocused = false
        dismissKeyboard()
        isDocumentPickerPresented = true
    }

    private func dismissCamera() {
        isCameraPresented = false
    }

    private func appendCapturedImage(_ image: UIImage) {
        appendLoadedImage(image)
        dismissCamera()
    }

    private func appendSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard Task.isCancelled == false else { return }

            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    continue
                }

                await MainActor.run {
                    appendLoadedImage(image)
                }
            } catch {
                await MainActor.run {
                    mediaAlertMessage = "读取图片失败，请换一张图片重试。"
                }
            }
        }
    }

    private func appendLoadedImage(_ image: UIImage) {
        guard let attachment = ChatImageAttachment.make(from: image) else {
            mediaAlertMessage = "处理图片失败，请换一张图片重试。"
            return
        }

        pendingImageAttachments.append(attachment)
        prefersTextInput = true
        isAttachmentDrawerPresented = false
        focusComposerTextField()
    }

    private func handlePickedDocuments(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard urls.isEmpty == false else { return }

            Task {
                do {
                    let importedDocuments = try ChatDocumentStore.importPickedFiles(from: urls)
                    await MainActor.run {
                        let existingIDs = Set(pendingDocumentAttachments.map(\.id))
                        let remainingSlots = max(4 - pendingDocumentAttachments.count, 0)
                        let deduplicated = importedDocuments.filter { existingIDs.contains($0.id) == false }
                        let appended = Array(deduplicated.prefix(remainingSlots))

                        pendingDocumentAttachments.append(contentsOf: appended)
                        prefersTextInput = true
                        isAttachmentDrawerPresented = false
                        if appended.isEmpty == false {
                            focusComposerTextField()
                        }
                        if importedDocuments.count > appended.count {
                            presentToast("最多同时添加 4 个文件")
                        }
                    }
                } catch {
                    await MainActor.run {
                        mediaAlertMessage = error.localizedDescription
                    }
                }
            }
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }
            mediaAlertMessage = error.localizedDescription
        }
    }

    private func removePendingAttachment(_ attachmentID: UUID) {
        pendingImageAttachments.removeAll { $0.id == attachmentID }

        if pendingImageAttachments.isEmpty,
           pendingDocumentAttachments.isEmpty,
           inputText.isEmpty {
            prefersTextInput = false
        }
    }

    private func removePendingDocument(_ attachmentID: UUID) {
        pendingDocumentAttachments.removeAll { $0.id == attachmentID }

        if pendingImageAttachments.isEmpty,
           pendingDocumentAttachments.isEmpty,
           inputText.isEmpty {
            prefersTextInput = false
        }
    }

    private func handleModeButtonTap() {
        if isTextMode {
            if inputText.isEmpty,
               pendingImageAttachments.isEmpty,
               pendingDocumentAttachments.isEmpty {
                prefersTextInput = false
                dismissTransientUI()
            } else {
                focusComposerTextField()
            }
        } else {
            prefersTextInput = true
            isAttachmentDrawerPresented = false
            focusComposerTextField()
        }
    }

    private func toggleAttachmentDrawer() {
        voiceInputController.cancelCapture()

        if isTextFieldFocused {
            isTextFieldFocused = false
            dismissKeyboard()
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isAttachmentDrawerPresented.toggle()
        }
    }

    private func beginVoiceCapture() {
        guard isTextMode == false else { return }

        isVoiceCancellationPending = false
        isAttachmentDrawerPresented = false
        dismissKeyboard()
        voicePlaybackController.stop()
        voiceInputController.beginCapture()
    }

    private func handleVoiceCancellationPendingChange(_ isPending: Bool) {
        guard isTextMode == false else { return }

        isVoiceCancellationPending = isPending
    }

    private func endVoiceCapture(_ cancelled: Bool) {
        guard isTextMode == false else { return }

        isVoiceCancellationPending = false

        if cancelled {
            voiceInputController.cancelCapture()
        } else {
            voiceInputController.endCapture()
        }
    }

    private func applyVoiceTranscript(_ transcript: String) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTranscript.isEmpty == false else { return }

        inputText = trimmedTranscript
        isAttachmentDrawerPresented = false
        prefersTextInput = true

        if voiceSendMode == .auto, isRequestingReply == false {
            handleSend()
        } else {
            focusComposerTextField()
        }
    }

    private func dismissTransientUI() {
        voiceInputController.cancelCapture()
        isVoiceCancellationPending = false
        isAttachmentDrawerPresented = false
        isTextFieldFocused = false
        if inputText.isEmpty,
           pendingImageAttachments.isEmpty,
           pendingDocumentAttachments.isEmpty {
            prefersTextInput = false
        }
        dismissKeyboard()
    }

    private func focusComposerTextField() {
        Task { @MainActor in
            await Task.yield()
            isTextFieldFocused = true
        }
    }

    private func handleSend() {
        guard canSend, let currentSessionID else { return }

        let prompt = resolvedPromptForSend()
        let attachments = pendingImageAttachments
        let documentAttachments = pendingDocumentAttachments
        let newUserMessage = ChatMessage(
            role: .user,
            text: prompt,
            attachments: attachments,
            documentAttachments: documentAttachments,
            showsActions: false
        )
        let assistantMessageID = UUID()
        let conversationSnapshot = beginStreamingAssistantTurn(
            with: newUserMessage,
            assistantMessageID: assistantMessageID,
            in: currentSessionID
        )

        replyTasks[currentSessionID]?.cancel()
        replyTasks[currentSessionID] = Task {
            await generateAssistantReply(
                for: conversationSnapshot,
                assistantMessageID: assistantMessageID,
                sessionID: currentSessionID
            )
        }
    }

    private func resolvedPromptForSend() -> String {
        guard trimmedInput.isEmpty else { return trimmedInput }

        if let firstDocument = pendingDocumentAttachments.first {
            switch firstDocument.kind {
            case .markdown:
                return "请先阅读我上传的 Markdown 文档，并告诉我可以如何继续编辑它。"
            case .pdf:
                return "请先阅读我上传的 PDF 文档，并概括核心内容。"
            case .other:
                return "请先阅读我上传的文件，并告诉我可以如何处理它。"
            }
        }

        return trimmedInput
    }

    private func runDemoScenario(_ scenario: ChatDemoScenario) {
        guard let currentSessionID, isRequestingReply == false else { return }

        let userMessage = ChatMessage(
            role: .user,
            text: demoScenarioPrompt(for: scenario),
            showsActions: false
        )
        let assistantMessageID = UUID()
        _ = beginStreamingAssistantTurn(
            with: userMessage,
            assistantMessageID: assistantMessageID,
            in: currentSessionID
        )

        replyTasks[currentSessionID]?.cancel()
        replyTasks[currentSessionID] = Task {
            await playDemoScenario(
                scenario,
                assistantMessageID: assistantMessageID,
                sessionID: currentSessionID
            )
        }
    }

    @discardableResult
    private func beginStreamingAssistantTurn(
        with userMessage: ChatMessage,
        assistantMessageID: UUID,
        in sessionID: UUID
    ) -> [ChatMessage] {
        let conversationSnapshot = messages + [userMessage]

        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
            messages.append(userMessage)
            messages.append(
                ChatMessage(
                    id: assistantMessageID,
                    role: .assistant,
                    text: "",
                    showsActions: false,
                    state: .streaming
                )
            )
        }

        inputText = ""
        pendingImageAttachments = []
        pendingDocumentAttachments = []
        isAttachmentDrawerPresented = false
        voiceInputController.cancelCapture()
        voicePlaybackController.stop()
        isTextFieldFocused = false
        prefersTextInput = false
        isRequestingReply = true
        currentRetryAttempt = 0
        activeAssistantMessageID = assistantMessageID
        retryAttemptsBySession[sessionID] = 0
        activeAssistantMessageIDsBySession[sessionID] = assistantMessageID
        updateMessages(messages, for: sessionID)
        scrollToBottomRequest += 1
        dismissKeyboard()
        persistCurrentSession()
        return conversationSnapshot
    }

    private func generateAssistantReply(
        for conversationSnapshot: [ChatMessage],
        assistantMessageID: UUID,
        sessionID: UUID
    ) async {
        await streamAssistantReply(
            assistantMessageID: assistantMessageID,
            sessionID: sessionID
        ) { typingBuffer in
            let configuration = OpenAIModelConfiguration(
                apiKey: openAIAPIKey,
                baseURL: openAIBaseURL,
                model: openAIModel
            )
            let service = try makeChatService(configuration)
            let requestTurns = conversationContextBuilder.makeTurns(from: conversationSnapshot)
            let reply = try await service.streamReply(
                for: requestTurns,
                timeoutInterval: 45,
                maxRetryCount: 1,
                onRetry: { retryAttempt in
                    await MainActor.run {
                        retryAttemptsBySession[sessionID] = retryAttempt
                        if currentSessionID == sessionID {
                            currentRetryAttempt = retryAttempt
                        }
                    }
                },
                onEvent: { event in
                    await handleStreamEvent(
                        event,
                        with: typingBuffer,
                        assistantMessageID: assistantMessageID,
                        sessionID: sessionID
                    )
                }
            )
            return reply
        }
    }

    private func playDemoScenario(
        _ scenario: ChatDemoScenario,
        assistantMessageID: UUID,
        sessionID: UUID
    ) async {
        await streamAssistantReply(
            assistantMessageID: assistantMessageID,
            sessionID: sessionID
        ) { typingBuffer in
            try await playDemoScenarioSteps(
                demoScenarioSteps(for: scenario),
                typingBuffer: typingBuffer,
                assistantMessageID: assistantMessageID,
                sessionID: sessionID
            )
            return demoScenarioFinalText(for: scenario)
        }
    }

    private func streamAssistantReply(
        assistantMessageID: UUID,
        sessionID: UUID,
        producer: @escaping @Sendable (TypewriterBuffer) async throws -> String
    ) async {
        let typingBuffer = TypewriterBuffer()
        let typingStream = await typingBuffer.stream()
        let typewriterTask = Task {
            await playTypewriter(
                from: typingStream,
                assistantMessageID: assistantMessageID,
                sessionID: sessionID
            )
        }

        do {
            let reply = try await producer(typingBuffer)
            await typingBuffer.finish()
            await typewriterTask.value

            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                retryAttemptsBySession[sessionID] = 0
                activeAssistantMessageIDsBySession.removeValue(forKey: sessionID)
                replyTasks.removeValue(forKey: sessionID)
                if let completedMessages = completeAssistantMessage(
                    id: assistantMessageID,
                    finalText: reply,
                    in: sessionID
                ) {
                    finishLiveMessages(completedMessages, for: sessionID)
                }
                if currentSessionID == sessionID {
                    syncReplyState(for: sessionID)
                }
            }
        } catch is CancellationError {
            await typingBuffer.finish()
            await typewriterTask.value

            await MainActor.run {
                retryAttemptsBySession.removeValue(forKey: sessionID)
                activeAssistantMessageIDsBySession.removeValue(forKey: sessionID)
                replyTasks.removeValue(forKey: sessionID)
                liveMessagesBySession.removeValue(forKey: sessionID)
                if currentSessionID == sessionID {
                    syncReplyState(for: sessionID)
                }
            }
        } catch {
            await typingBuffer.finish()
            await typewriterTask.value

            let fallbackText = "请求失败：\(error.localizedDescription)"
            await MainActor.run {
                retryAttemptsBySession[sessionID] = 0
                activeAssistantMessageIDsBySession.removeValue(forKey: sessionID)
                replyTasks.removeValue(forKey: sessionID)
                if let failedMessages = failAssistantMessage(
                    id: assistantMessageID,
                    fallbackText: fallbackText,
                    in: sessionID
                ) {
                    finishLiveMessages(failedMessages, for: sessionID)
                }
                if currentSessionID == sessionID {
                    syncReplyState(for: sessionID)
                }
            }
        }
    }

    private func handleStreamEvent(
        _ event: ChatStreamEvent,
        with typingBuffer: TypewriterBuffer,
        assistantMessageID: UUID,
        sessionID: UUID
    ) async {
        switch event {
        case .textDelta(let delta):
            await typingBuffer.enqueue(delta)
        case .toolCall(let toolCall):
            await MainActor.run {
                upsertToolCall(toolCall, on: assistantMessageID, in: sessionID)
            }
        }
    }

    private func playDemoScenarioSteps(
        _ steps: [DemoStreamStep],
        typingBuffer: TypewriterBuffer,
        assistantMessageID: UUID,
        sessionID: UUID
    ) async throws {
        for step in steps {
            try Task.checkCancellation()

            switch step {
            case .pause(let duration):
                try await Task.sleep(nanoseconds: duration)
            case .text(let value):
                await handleStreamEvent(
                    .textDelta(value),
                    with: typingBuffer,
                    assistantMessageID: assistantMessageID,
                    sessionID: sessionID
                )
            case .tool(let toolCall):
                await handleStreamEvent(
                    .toolCall(toolCall),
                    with: typingBuffer,
                    assistantMessageID: assistantMessageID,
                    sessionID: sessionID
                )
            }
        }
    }

    private func playTypewriter(
        from stream: AsyncStream<String>,
        assistantMessageID: UUID,
        sessionID: UUID
    ) async {
        for await character in stream {
            await MainActor.run {
                appendText(character, to: assistantMessageID, in: sessionID)
            }
            try? await Task.sleep(nanoseconds: typewriterDelay(for: character))
        }
    }

    private func appendText(_ text: String, to messageID: UUID, in sessionID: UUID) {
        var sessionMessages = messages(for: sessionID)
        guard let index = sessionMessages.firstIndex(where: { $0.id == messageID }) else { return }

        sessionMessages[index].text.append(text)
        sessionMessages[index].state = .streaming
        sessionMessages[index].showsActions = false
        updateMessages(sessionMessages, for: sessionID)

        if currentSessionID == sessionID {
            currentRetryAttempt = 0
        }
    }

    private func upsertToolCall(_ toolCall: ChatToolCall, on messageID: UUID, in sessionID: UUID) {
        var sessionMessages = messages(for: sessionID)
        guard let messageIndex = sessionMessages.firstIndex(where: { $0.id == messageID }) else { return }

        if let toolCallIndex = sessionMessages[messageIndex].toolCalls.firstIndex(where: { $0.id == toolCall.id }) {
            sessionMessages[messageIndex].toolCalls[toolCallIndex] = toolCall
        } else {
            sessionMessages[messageIndex].toolCalls.append(toolCall)
        }

        sessionMessages[messageIndex].state = .streaming
        sessionMessages[messageIndex].showsActions = false
        updateMessages(sessionMessages, for: sessionID)
        scrollToBottomRequest += 1

        if currentSessionID == sessionID {
            currentRetryAttempt = 0
        }
    }

    private func completeAssistantMessage(id: UUID, finalText: String, in sessionID: UUID) -> [ChatMessage]? {
        var sessionMessages = messages(for: sessionID)
        guard let index = sessionMessages.firstIndex(where: { $0.id == id }) else { return nil }

        if sessionMessages[index].text.isEmpty {
            sessionMessages[index].text = finalText
        }
        sessionMessages[index].state = .complete
        sessionMessages[index].showsActions = true
        updateMessages(sessionMessages, for: sessionID)
        return sessionMessages
    }

    private func failAssistantMessage(id: UUID, fallbackText: String, in sessionID: UUID) -> [ChatMessage]? {
        var sessionMessages = messages(for: sessionID)
        guard let index = sessionMessages.firstIndex(where: { $0.id == id }) else { return nil }

        if sessionMessages[index].text.isEmpty {
            sessionMessages[index].text = fallbackText
        } else {
            sessionMessages[index].text.append("\n\n\(fallbackText)")
        }
        sessionMessages[index].state = .failed
        sessionMessages[index].showsActions = false
        updateMessages(sessionMessages, for: sessionID)
        return sessionMessages
    }

    private func demoScenarioPrompt(for scenario: ChatDemoScenario) -> String {
        switch scenario {
        case .richStreaming:
            return "请演示支持 Markdown、代码块和 Tool Call 卡片的流式渲染。"
        case .toolFailure:
            return "请演示工具调用失败时的流式卡片状态。"
        }
    }

    private func demoScenarioFinalText(for scenario: ChatDemoScenario) -> String {
        switch scenario {
        case .richStreaming:
            return """
            ### 流式渲染验收

            - Markdown 列表会边生成边排版
            - Tool Call 卡片会先于正文出现
            - 代码块在围栏闭合前也会保留代码样式

            > 上方的时间与天气预报卡片，就是和正文混排的流式组件。

            ```swift
            struct StreamRenderer {
                func renderNextFrame() {
                    print("markdown + code + tool cards")
                }
            }
            ```

            最后一段正文会继续按字追加，验证完整回复结束后，卡片与代码块都保持稳定布局。
            """
        case .toolFailure:
            return """
            ### Tool Call 失败态

            - 当工具返回错误时，卡片会切换到失败样式
            - 参数与结果依然保留，方便排查

            上方卡片模拟的是“定位权限未开启”的场景，正文会继续流式输出，不会因为单个工具失败导致整个渲染链路中断。
            """
        }
    }

    private func demoScenarioSteps(for scenario: ChatDemoScenario) -> [DemoStreamStep] {
        switch scenario {
        case .richStreaming:
            return [
                .pause(220_000_000),
                .tool(
                    ChatToolCall(
                        id: "demo_datetime",
                        name: "get_current_datetime",
                        argumentsJSON: "{}",
                        output: nil,
                        status: .running
                    )
                ),
                .pause(420_000_000),
                .tool(
                    ChatToolCall(
                        id: "demo_datetime",
                        name: "get_current_datetime",
                        argumentsJSON: "{}",
                        output: """
                        {"ok":true,"calendarDate":"2026-04-20","timeText":"14:32","weekdayText":"星期一","timeZoneIdentifier":"Asia/Shanghai"}
                        """,
                        status: .succeeded
                    )
                ),
                .pause(220_000_000),
                .tool(
                    ChatToolCall(
                        id: "demo_forecast",
                        name: "get_weather_forecast",
                        argumentsJSON: """
                        {"locationQuery":"上海","useCurrentLocation":false,"startDayOffset":1,"dayCount":2}
                        """,
                        output: nil,
                        status: .running
                    )
                ),
                .pause(620_000_000),
                .tool(
                    ChatToolCall(
                        id: "demo_forecast",
                        name: "get_weather_forecast",
                        argumentsJSON: """
                        {"locationQuery":"上海","useCurrentLocation":false,"startDayOffset":1,"dayCount":2}
                        """,
                        output: """
                        {"ok":true,"locationName":"上海","dailyForecasts":[{"date":"2026-04-21","weatherSummary":"多云","maxTemperatureCelsius":24,"minTemperatureCelsius":17},{"date":"2026-04-22","weatherSummary":"小雨","maxTemperatureCelsius":22,"minTemperatureCelsius":16}]}
                        """,
                        status: .succeeded
                    )
                ),
                .pause(260_000_000),
                .text(demoScenarioFinalText(for: .richStreaming))
            ]
        case .toolFailure:
            return [
                .pause(180_000_000),
                .tool(
                    ChatToolCall(
                        id: "demo_location",
                        name: "get_current_location",
                        argumentsJSON: "{}",
                        output: nil,
                        status: .running
                    )
                ),
                .pause(480_000_000),
                .tool(
                    ChatToolCall(
                        id: "demo_location",
                        name: "get_current_location",
                        argumentsJSON: "{}",
                        output: """
                        {"ok":false,"error":"定位权限未开启，请在系统设置中允许访问当前位置。"}
                        """,
                        status: .failed
                    )
                ),
                .pause(200_000_000),
                .text(demoScenarioFinalText(for: .toolFailure))
            ]
        }
    }

    private func typewriterDelay(for character: String) -> UInt64 {
        if character == "\n" {
            return 34_000_000
        }

        if "，。！？,.!?；：;:".contains(character) {
            return 42_000_000
        }

        return 18_000_000
    }

    private func toggleAssistantMessageAudio(_ message: ChatMessage) {
        guard isPlayableAssistantMessage(message) else { return }
        voicePlaybackController.togglePlayback(for: message)
    }

    private func handleAssistantMessageCopy(_ message: ChatMessage) {
        UIPasteboard.general.string = message.text
        presentToast("已复制到剪贴板")
    }

    private func handleUserMessageCopy(_ message: ChatMessage) {
        UIPasteboard.general.string = message.text
        presentToast("已复制到剪贴板")
    }

    private func toggleAssistantMessageFavorite(_ message: ChatMessage) {
        guard let currentSessionID, message.role == .assistant else { return }
        setFavoriteState(isFavorite: message.isFavorite == false, for: message.id, in: currentSessionID)
    }

    private func playLatestAssistantReply() {
        guard let latestPlayableAssistantMessage else { return }
        voicePlaybackController.togglePlayback(for: latestPlayableAssistantMessage)
    }

    private func isPlayableAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant, message.state == .complete else {
            return false
        }

        return message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func setFavoriteState(isFavorite: Bool, for messageID: UUID, in sessionID: UUID) {
        var sessionMessages = messages(for: sessionID)
        guard let index = sessionMessages.firstIndex(where: { $0.id == messageID }) else { return }

        sessionMessages[index].favoritedAt = isFavorite ? Date() : nil
        persistMessages(sessionMessages, for: sessionID, shouldRefreshTimestamp: false)

        presentToast(isFavorite ? "已收藏" : "已取消收藏")
    }

    private func openFavoritedMessage(_ entry: FavoritedMessageEntry) {
        selectedSidebarItem = .chat

        if let selectedSession = sessionStore.selectSession(id: entry.sessionID) {
            loadSession(selectedSession)
        }
    }

    private func removeFavorite(_ entry: FavoritedMessageEntry) {
        setFavoriteState(isFavorite: false, for: entry.message.id, in: entry.sessionID)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ContentView()
}
