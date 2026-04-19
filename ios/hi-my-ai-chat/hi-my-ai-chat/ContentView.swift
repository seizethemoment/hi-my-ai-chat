//
//  ContentView.swift
//  hi-my-ai-chat
//
//  Created by 李俊鹏 on 2026/4/17.
//

import SwiftUI
import PhotosUI
import UIKit

private enum SidebarItem: String, CaseIterable, Identifiable {
    case chat
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "聊天"
        case .favorites:
            return "收藏"
        }
    }

    var systemImage: String {
        switch self {
        case .chat:
            return "message"
        case .favorites:
            return "bookmark"
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    enum State {
        case streaming
        case complete
        case failed
    }

    let id: UUID
    let role: Role
    var text: String
    var attachments: [ChatImageAttachment]
    var showsActions: Bool
    var state: State

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        attachments: [ChatImageAttachment] = [],
        showsActions: Bool,
        state: State = .complete
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.showsActions = showsActions
        self.state = state
    }
}

struct ChatImageAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let data: Data
    let mimeType: String

    init(
        id: UUID = UUID(),
        data: Data,
        mimeType: String = "image/jpeg"
    ) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
    }

    var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    var image: UIImage? {
        UIImage(data: data)
    }

    static func make(from image: UIImage, maxDimension: CGFloat = 1_600) -> ChatImageAttachment? {
        let normalizedImage = image.normalizedForAttachment(maxDimension: maxDimension)
        guard let data = normalizedImage.jpegData(compressionQuality: 0.82) else {
            return nil
        }

        return ChatImageAttachment(data: data)
    }
}

private struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let prompt: String
}

private struct AttachmentAction: Identifiable {
    enum Source {
        case camera
        case photoLibrary
    }

    let id = UUID()
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let source: Source
}

struct ContentView: View {
    @StateObject private var sessionStore = ChatSessionStore()
    @StateObject private var voiceInputController = VoiceInputController()
    @AppStorage("voice_auto_send_enabled") private var isVoiceAutoSendEnabled = true
    @AppStorage(OpenAISettings.apiKeyStorageKey) private var openAIAPIKey = ""
    @AppStorage(OpenAISettings.baseURLStorageKey) private var openAIBaseURL = ""
    @AppStorage(OpenAISettings.modelStorageKey) private var openAIModel = ""
    @State private var selectedSidebarItem: SidebarItem? = .chat
    @State private var isSidebarPresented = false
    @State private var sidebarDragOffset: CGFloat = 0
    @State private var currentSessionID: UUID?
    @State private var isSidebarEditingSessions = false
    @State private var isSidebarSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var isSidebarDrawerMounted = false
    @State private var recentSearchTerms = SidebarSearchHistoryStore.load()
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var pendingImageAttachments: [ChatImageAttachment] = []
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
    @State private var voiceToastMessage: String?
    @State private var mediaAlertMessage: String?
    @State private var prefersTextInput = false
    @State private var replyTasks: [UUID: Task<Void, Never>] = [:]
    @State private var liveMessagesBySession: [UUID: [ChatMessage]] = [:]
    @State private var retryAttemptsBySession: [UUID: Int] = [:]
    @State private var activeAssistantMessageIDsBySession: [UUID: UUID] = [:]
    @State private var activeAssistantMessageID: UUID?
    @State private var scrollToBottomRequest = 0
    @State private var voiceToastDismissTask: Task<Void, Never>?
    @State private var sidebarUnmountTask: Task<Void, Never>?
    @FocusState private var isTextFieldFocused: Bool

    private let quickActions = [
        QuickAction(title: "写一首关于季节的古诗", systemImage: "leaf", prompt: "写一首关于季节的古诗"),
        QuickAction(title: "讲一个笑话给我听", systemImage: "face.smiling", prompt: "讲一个笑话给我听"),
        QuickAction(title: "随便说点什么", systemImage: "ellipsis.bubble", prompt: "随便说点什么")
    ]

    private let imageQuickActions = [
        QuickAction(title: "这是什么", systemImage: "questionmark.circle", prompt: "这是什么？"),
        QuickAction(title: "图片配文", systemImage: "text.quote", prompt: "帮我为这张图片写一段配文。"),
        QuickAction(title: "提取图中文字", systemImage: "text.viewfinder", prompt: "请提取这张图片里的所有文字。"),
        QuickAction(title: "翻译图中文字", systemImage: "globe", prompt: "请识别并翻译这张图片里的文字。")
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
        )
    ]

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPendingAttachments: Bool {
        pendingImageAttachments.isEmpty == false
    }

    private var canSend: Bool {
        (trimmedInput.isEmpty == false || hasPendingAttachments) && isRequestingReply == false
    }

    private var isTextMode: Bool {
        prefersTextInput || inputText.isEmpty == false || hasPendingAttachments
    }

    private var activeQuickActions: [QuickAction] {
        hasPendingAttachments ? imageQuickActions : quickActions
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
            let showsSidebarDrawer = isSidebarDrawerMounted || isSidebarPresented || sidebarDragOffset != 0

            ZStack(alignment: .leading) {
                chatDetailView
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
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 6,
            matching: .images,
            photoLibrary: .shared()
        )
        .task(id: selectedPhotoItems.count) {
            let items = selectedPhotoItems
            guard items.isEmpty == false else { return }

            await appendSelectedPhotoItems(items)
            selectedPhotoItems = []
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
                    onTitleTap: promptRenameCurrentSession
                )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                ChatMessagesView(
                    messages: messages,
                    scrollToBottomRequest: scrollToBottomRequest,
                    canDeleteMessages: isRequestingReply == false,
                    onDeleteMessage: deleteMessage
                ) {
                    dismissTransientUI()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    if let voiceToastMessage {
                        InlineToastView(message: voiceToastMessage)
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
                        onQuickActionTap: applyQuickAction,
                        onPrimaryAttachmentTap: presentCamera,
                        onModeButtonTap: handleModeButtonTap,
                        onAttachmentTap: toggleAttachmentDrawer,
                        onAttachmentActionTap: handleAttachmentAction,
                        onRemovePendingAttachment: removePendingAttachment,
                        onVoicePressBegan: beginVoiceCapture,
                        onVoiceCancelPreviewChanged: handleVoiceCancellationPendingChange,
                        onVoicePressEnded: endVoiceCapture,
                        onSend: handleSend
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .animation(.easeInOut(duration: 0.18), value: voiceToastMessage)
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
            presentVoiceToast(message)
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

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isSidebarPresented = true
            sidebarDragOffset = 0
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
            isSidebarPresented = false
            sidebarDragOffset = 0
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
        selectedSidebarItem = .chat
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

        updatedMessages.remove(at: index)
        messages = updatedMessages
        liveMessagesBySession.removeValue(forKey: currentSessionID)
        sessionStore.updateMessages(updatedMessages, for: currentSessionID)
    }

    private func loadSession(_ session: ChatSession) {
        voiceInputController.cancelCapture()
        voiceToastDismissTask?.cancel()
        sidebarUnmountTask?.cancel()
        let sessionMessages = messages(for: session.id, fallback: session.messages)
        currentSessionID = session.id
        messages = sessionMessages
        inputText = ""
        pendingImageAttachments = []
        selectedPhotoItems = []
        isVoiceCancellationPending = false
        voiceToastMessage = nil
        mediaAlertMessage = nil
        renameSessionDraft = ""
        isRenameSessionAlertPresented = false
        isAttachmentDrawerPresented = false
        isPhotoPickerPresented = false
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
                guard isSidebarPresented == false, sidebarDragOffset == 0 else { return }
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

    private func presentVoiceToast(_ message: String) {
        voiceToastDismissTask?.cancel()

        withAnimation(.easeInOut(duration: 0.18)) {
            voiceToastMessage = message
        }

        voiceToastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    voiceToastMessage = nil
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

    private func sidebarOffset(drawerWidth: CGFloat) -> CGFloat {
        if isSidebarPresented {
            return min(0, sidebarDragOffset)
        }

        return -drawerWidth + max(0, sidebarDragOffset)
    }

    private func sidebarRevealedWidth(drawerWidth: CGFloat) -> CGFloat {
        min(max(drawerWidth + sidebarOffset(drawerWidth: drawerWidth), 0), drawerWidth)
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
                sidebarDragOffset = min(drawerWidth, value.translation.width)
            }
            .onEnded { value in
                guard isSidebarPresented == false else { return }
                guard value.startLocation.x <= 44 else {
                    sidebarDragOffset = 0
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    sidebarDragOffset = 0
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
                sidebarDragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    sidebarDragOffset = 0
                    return
                }

                let shouldClose = value.translation.width < -drawerWidth * 0.22
                    || value.predictedEndTranslation.width < -drawerWidth * 0.34

                if shouldClose {
                    closeSidebar()
                } else {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        isSidebarPresented = true
                        sidebarDragOffset = 0
                    }
                }
            }
    }

    private func applyQuickAction(_ action: QuickAction) {
        inputText = action.prompt
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

    private func removePendingAttachment(_ attachmentID: UUID) {
        pendingImageAttachments.removeAll { $0.id == attachmentID }

        if pendingImageAttachments.isEmpty, inputText.isEmpty {
            prefersTextInput = false
        }
    }

    private func handleModeButtonTap() {
        if isTextMode {
            if inputText.isEmpty, pendingImageAttachments.isEmpty {
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
        if inputText.isEmpty, pendingImageAttachments.isEmpty {
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

        let prompt = trimmedInput
        let attachments = pendingImageAttachments
        let newUserMessage = ChatMessage(
            role: .user,
            text: prompt,
            attachments: attachments,
            showsActions: false
        )
        let conversationSnapshot = messages + [newUserMessage]
        let assistantMessageID = UUID()

        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
            messages.append(newUserMessage)
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
        isAttachmentDrawerPresented = false
        voiceInputController.cancelCapture()
        isTextFieldFocused = false
        prefersTextInput = false
        isRequestingReply = true
        currentRetryAttempt = 0
        activeAssistantMessageID = assistantMessageID
        retryAttemptsBySession[currentSessionID] = 0
        activeAssistantMessageIDsBySession[currentSessionID] = assistantMessageID
        updateMessages(messages, for: currentSessionID)
        scrollToBottomRequest += 1
        dismissKeyboard()
        persistCurrentSession()

        replyTasks[currentSessionID]?.cancel()
        replyTasks[currentSessionID] = Task {
            await generateAssistantReply(
                for: conversationSnapshot,
                assistantMessageID: assistantMessageID,
                sessionID: currentSessionID
            )
        }
    }

    private func generateAssistantReply(
        for conversationSnapshot: [ChatMessage],
        assistantMessageID: UUID,
        sessionID: UUID
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
            let configuration = OpenAIModelConfiguration(
                apiKey: openAIAPIKey,
                baseURL: openAIBaseURL,
                model: openAIModel
            )
            let service = try OpenAIChatService(configuration: configuration)
            let reply = try await service.streamReply(
                for: conversationSnapshot.map { message in
                    OpenAIChatTurn(
                        role: message.role == .user ? .user : .assistant,
                        text: message.text,
                        imageDataURLs: message.attachments.map(\.dataURL)
                    )
                },
                onRetry: { retryAttempt in
                    await MainActor.run {
                        retryAttemptsBySession[sessionID] = retryAttempt
                        if currentSessionID == sessionID {
                            currentRetryAttempt = retryAttempt
                        }
                    }
                },
                onDelta: { delta in
                    await typingBuffer.enqueue(delta)
                }
            )

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

    private func typewriterDelay(for character: String) -> UInt64 {
        if character == "\n" {
            return 34_000_000
        }

        if "，。！？,.!?；：;:".contains(character) {
            return 42_000_000
        }

        return 18_000_000
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private actor TypewriterBuffer {
    private let pair = AsyncStream.makeStream(of: String.self)

    func stream() -> AsyncStream<String> {
        pair.stream
    }

    func enqueue(_ text: String) {
        guard text.isEmpty == false else { return }

        for character in text {
            pair.continuation.yield(String(character))
        }
    }

    func finish() {
        pair.continuation.finish()
    }
}

private struct HomeBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.992, green: 0.992, blue: 0.989)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct TopBarView: View {
    let title: String
    let subtitle: String
    let onMenuTap: () -> Void
    let onTitleTap: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button(action: onMenuTap) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("菜单")
                .accessibilityIdentifier("top_menu_button")

                Spacer()

                HStack(spacing: 14) {
                    Button(action: {}) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 1.0))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("语音播报")
                    .accessibilityIdentifier("top_audio_button")
                }
            }

            Button(action: onTitleTap) {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .accessibilityIdentifier("top_title")

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.28))
                        .accessibilityIdentifier("top_subtitle")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("top_title_button")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SidebarDrawerView: View {
    @Binding var selectedItem: SidebarItem?
    let selectedSessionID: UUID?
    let sessions: [ChatSession]
    let isEditingSessions: Bool
    let revealProgress: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onSearchTap: () -> Void
    let onEditTap: () -> Void
    let onSettingsTap: () -> Void
    let onItemTap: () -> Void
    let onSessionTap: (ChatSession) -> Void
    let onDeleteSessionTap: (ChatSession) -> Void
    let onNewChatTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    sidebarMenu
                    sessionSection
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            bottomBar
        }
        .padding(.top, topInset + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1)
        }
        .shadow(color: Color.black.opacity(0.18 * revealProgress), radius: 22, x: 8, y: 0)
        .accessibilityIdentifier("sidebar_drawer")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("HiChat")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))

                Text("你的 AI 聊天助手")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                headerIconButton(
                    systemImage: "magnifyingglass",
                    accessibilityIdentifier: "sidebar_open_search_button",
                    action: onSearchTap
                )

                headerIconButton(
                    systemImage: "plus",
                    accessibilityIdentifier: "sidebar_new_chat_button",
                    action: onNewChatTap
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private func headerIconButton(
        systemImage: String,
        isActive: Bool = false,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.black.opacity(0.76))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isActive ? Color(red: 0.10, green: 0.54, blue: 1.0) : Color(red: 0.96, green: 0.97, blue: 0.99))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var sidebarMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SidebarItem.allCases) { item in
                Button {
                    selectedItem = item
                    onItemTap()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 22)

                        Text(item.title)
                            .font(.system(size: 17, weight: .semibold))

                        Spacer()
                    }
                    .foregroundStyle(selectedItem == item ? Color.white : Color.black.opacity(0.78))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selectedItem == item ? Color(red: 0.10, green: 0.54, blue: 1.0) : Color(red: 0.97, green: 0.98, blue: 0.99))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar_item_\(item.id)")
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer(minLength: 0)

            headerIconButton(
                systemImage: "gearshape",
                accessibilityIdentifier: "sidebar_settings_button",
                action: onSettingsTap
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, bottomInset + 24)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("最近会话")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.38))

                Spacer(minLength: 0)

                headerIconButton(
                    systemImage: "square.and.pencil",
                    isActive: isEditingSessions,
                    accessibilityIdentifier: "sidebar_edit_button",
                    action: onEditTap
                )
            }

            if sessions.isEmpty {
                Text("没有匹配的会话")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))
                    .padding(.top, 2)
            } else {
                ForEach(sessions) { session in
                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            onSessionTap(session)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedSessionID == session.id ? "message.fill" : "clock")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selectedSessionID == session.id ? Color(red: 0.10, green: 0.54, blue: 1.0) : Color.black.opacity(0.42))
                                    .frame(width: 18, height: 18)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.black.opacity(0.76))
                                        .lineLimit(1)

                                    Text(session.previewText)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.36))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        selectedSessionID == session.id
                                            ? Color(red: 0.94, green: 0.97, blue: 1.0)
                                            : Color.black.opacity(0.001)
                                    )
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar_session_\(session.id.uuidString)")

                        if isEditingSessions {
                            Button {
                                onDeleteSessionTap(session)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.48))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(Color(red: 0.96, green: 0.97, blue: 0.99))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sidebar_delete_session_\(session.id.uuidString)")
                        }
                    }
                }
            }
        }
    }
}

private struct SidebarSearchView: View {
    let sessions: [ChatSession]
    let recentSearchTerms: [String]
    let onDismiss: () -> Void
    let onRemoveRecentSearch: (String) -> Void
    let onSelectRecentSearch: (String) -> Void
    let onSelectSession: (ChatSession, String) -> Void

    @State private var query = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [ChatSession] {
        guard trimmedQuery.isEmpty == false else { return [] }

        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(trimmedQuery)
                || session.previewText.localizedCaseInsensitiveContains(trimmedQuery)
                || session.messages.contains(where: { message in
                    message.text.localizedCaseInsensitiveContains(trimmedQuery)
                })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.28))

                    TextField("搜索消息、智能体", text: $query)
                        .font(.system(size: 16, weight: .medium))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.black.opacity(0.78))
                        .submitLabel(.search)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            guard let firstMatch = searchResults.first else { return }
                            onSelectRecentSearch(trimmedQuery)
                            onSelectSession(firstMatch, trimmedQuery)
                        }
                        .accessibilityIdentifier("sidebar_search_page_input")
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                )

                Button("取消", action: onDismiss)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.74))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar_search_cancel_button")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if trimmedQuery.isEmpty {
                        ForEach(recentSearchTerms, id: \.self) { term in
                            HStack(spacing: 12) {
                                Button {
                                    query = term
                                    isSearchFieldFocused = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color.black.opacity(0.36))

                                        Text(term)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.82))

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("sidebar_search_history_\(term)")

                                Button {
                                    onRemoveRecentSearch(term)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.black.opacity(0.28))
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 18)
                                .accessibilityIdentifier("sidebar_search_history_remove_\(term)")
                            }
                        }
                    } else if searchResults.isEmpty {
                        Text("没有找到匹配的会话")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.34))
                            .padding(.horizontal, 18)
                            .padding(.top, 22)
                    } else {
                        ForEach(searchResults) { session in
                            Button {
                                onSelectRecentSearch(trimmedQuery)
                                onSelectSession(session, trimmedQuery)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.black.opacity(0.36))
                                        .frame(width: 16, height: 16)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.82))
                                            .lineLimit(1)

                                        Text(session.previewText)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.32))
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sidebar_search_result_\(session.id.uuidString)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.ignoresSafeArea())
        .task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            isSearchFieldFocused = true
        }
    }
}

private struct SettingsView: View {
    @Binding var isVoiceAutoSendEnabled: Bool
    @Binding var openAIAPIKey: String
    @Binding var openAIBaseURL: String
    @Binding var openAIModel: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.975, blue: 0.982)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings_back_button")

                    Spacer()

                    Text("设置")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))

                    Spacer()

                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("OpenAI 兼容模型")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.38))

                            VStack(alignment: .leading, spacing: 12) {
                                Text("聊天回复会读取这里配置的 API Key、Base URL 和 Model。输入后会保存在本机，下次打开仍会记住；API Key 在展示时会自动脱敏。")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.44))
                                    .fixedSize(horizontal: false, vertical: true)

                                SettingsAPIKeyField(
                                    title: "API Key",
                                    placeholder: "输入 API Key",
                                    text: $openAIAPIKey,
                                    accessibilityIdentifier: "settings_openai_api_key_field"
                                )

                                SettingsInputField(
                                    title: "Base URL",
                                    placeholder: "https://api.openai.com/v1",
                                    text: $openAIBaseURL,
                                    keyboardType: .URL,
                                    accessibilityIdentifier: "settings_openai_base_url_field"
                                )

                                SettingsInputField(
                                    title: "Model",
                                    placeholder: "gpt-5-mini",
                                    text: $openAIModel,
                                    keyboardType: .default,
                                    accessibilityIdentifier: "settings_openai_model_field"
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("语音输入")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.38))

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("自动发送语音输入")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Color.black.opacity(0.82))

                                    Text("开启后，松开“按住说话”会直接发送；关闭后会先写入输入框。")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.44))
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 12)

                                Toggle("", isOn: $isVoiceAutoSendEnabled)
                                    .labelsHidden()
                                    .tint(Color(red: 0.10, green: 0.54, blue: 1.0))
                                    .accessibilityIdentifier("settings_voice_auto_send_toggle")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

private struct SettingsInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.52))

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.84))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboardType)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

private struct SettingsAPIKeyField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let accessibilityIdentifier: String

    @FocusState private var isFocused: Bool
    @State private var isEditing = false

    private var maskedText: String {
        OpenAISettings.maskedAPIKey(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.52))

            Group {
                if isEditing {
                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(endEditing)
                        .onAppear {
                            Task { @MainActor in
                                await Task.yield()
                                isFocused = true
                            }
                        }
                } else {
                    Button(action: beginEditing) {
                        HStack(spacing: 8) {
                            Text(maskedText.isEmpty ? placeholder : maskedText)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(maskedText.isEmpty ? Color.black.opacity(0.28) : Color.black.opacity(0.84))
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            if maskedText.isEmpty == false {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.28))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.default)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .onChange(of: isFocused) { _, focused in
            if focused == false {
                endEditing()
            }
        }
    }

    private func beginEditing() {
        isEditing = true
    }

    private func endEditing() {
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        isFocused = false
    }
}

private struct ChatMessagesView: View {
    let messages: [ChatMessage]
    let scrollToBottomRequest: Int
    let canDeleteMessages: Bool
    let onDeleteMessage: (ChatMessage) -> Void
    let onBackgroundTap: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        LazyVStack(spacing: 16) {
                            if messages.isEmpty {
                                Color.clear
                                    .frame(height: 1)
                                    .id("chat_empty_anchor")
                            } else {
                                ForEach(messages) { message in
                                    MessageBubbleRow(
                                        message: message,
                                        canDelete: canDeleteMessages,
                                        onDelete: onDeleteMessage
                                    )
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("chat_bottom_anchor")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(minHeight: max(proxy.size.height - 24, 0), alignment: .bottom)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .accessibilityIdentifier("chat_messages_scroll")
                .onChange(of: scrollToBottomRequest, initial: false) { _, _ in
                    scheduleScrollToBottom(using: scrollProxy, animated: true)
                }
                .onChange(of: messages.last?.id, initial: true) { _, _ in
                    scheduleScrollToBottom(using: scrollProxy, animated: true)
                }
                .onChange(of: messages.last?.text ?? "", initial: false) { _, _ in
                    scrollToBottom(using: scrollProxy, animated: false)
                }
            }
        }
    }

    private func scheduleScrollToBottom(using scrollProxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            scrollToBottom(using: scrollProxy, animated: animated)
        }
    }

    private func scrollToBottom(using scrollProxy: ScrollViewProxy, animated: Bool) {
        guard messages.isEmpty == false else { return }

        let action = {
            scrollProxy.scrollTo("chat_bottom_anchor", anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                action()
            }
        } else {
            action()
        }
    }
}

private struct MessageBubbleRow: View {
    let message: ChatMessage
    let canDelete: Bool
    let onDelete: (ChatMessage) -> Void

    var body: some View {
        HStack {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 10) {
                    bubble(
                        background: assistantBackgroundColor,
                        foreground: assistantForegroundColor,
                        alignment: .leading
                    )

                    if message.state == .streaming {
                        StreamingMessageStatusView()
                    } else if message.showsActions {
                        AssistantMessageActionsView(messageText: message.text)
                    }
                }

                Spacer(minLength: 56)
            } else {
                Spacer(minLength: 56)

                bubble(
                    background: Color(red: 0.11, green: 0.67, blue: 0.99),
                    foreground: .white,
                    alignment: .trailing
                )
            }
        }
        .frame(maxWidth: .infinity)
        .id(message.id)
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    onDelete(message)
                } label: {
                    Label("删除消息", systemImage: "trash")
                }
            }
        }
    }

    private var assistantBackgroundColor: Color {
        if message.state == .failed {
            return Color(red: 0.995, green: 0.944, blue: 0.944)
        }

        return Color(red: 0.955, green: 0.958, blue: 0.965)
    }

    private var assistantForegroundColor: Color {
        if message.state == .failed {
            return Color(red: 0.78, green: 0.24, blue: 0.20)
        }

        return Color.black.opacity(0.78)
    }

    private func bubble(background: Color, foreground: Color, alignment: Alignment) -> some View {
        Group {
            if message.state == .streaming, message.text.isEmpty, message.attachments.isEmpty {
                TypingIndicatorView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: message.text.isEmpty || message.attachments.isEmpty ? 0 : 10) {
                    if message.attachments.isEmpty == false {
                        MessageAttachmentGridView(attachments: message.attachments)
                    }

                    if message.text.isEmpty == false {
                        Text(message.text)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(foreground)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 288, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(background)
            )
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private struct MessageAttachmentGridView: View {
    let attachments: [ChatImageAttachment]

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 6),
            count: attachments.count == 1 ? 1 : 2
        )
    }

    private var itemHeight: CGFloat {
        attachments.count == 1 ? 188 : 108
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(attachments) { attachment in
                ChatAttachmentThumbnailView(
                    attachment: attachment,
                    height: itemHeight,
                    cornerRadius: 12
                )
            }
        }
    }
}

private struct PendingAttachmentStripView: View {
    let attachments: [ChatImageAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        ChatAttachmentThumbnailView(
                            attachment: attachment,
                            width: 84,
                            height: 84,
                            cornerRadius: 16
                        )

                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.black.opacity(0.68)))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct ChatAttachmentThumbnailView: View {
    let attachment: ChatImageAttachment
    var width: CGFloat? = nil
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = attachment.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.06))

                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.28))
                }
            }
        }
        .frame(maxWidth: width == nil ? .infinity : width, alignment: .center)
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct TypingIndicatorView: View {
    @State private var activeDot = 0

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.black.opacity(activeDot == index ? 0.60 : 0.22))
                    .frame(width: 8, height: 8)
                    .scaleEffect(activeDot == index ? 1.05 : 0.82)
            }
        }
        .frame(height: 22)
        .task {
            while Task.isCancelled == false {
                activeDot = (activeDot + 1) % 3
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
    }
}

private struct StreamingMessageStatusView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)

            Text("生成中")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.35))
        }
        .padding(.leading, 2)
    }
}

private struct AssistantMessageActionsView: View {
    let messageText: String

    var body: some View {
        HStack(spacing: 10) {
            actionButton(systemImage: "doc.on.doc") {
                UIPasteboard.general.string = messageText
            }

            actionButton(systemImage: "speaker.wave.2.fill") {}

            actionButton(systemImage: "bookmark") {}
        }
        .padding(.leading, 2)
    }

    private func actionButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 1.0))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ComposerDockView: View {
    @Binding var text: String
    @Binding var isAttachmentDrawerPresented: Bool
    let isTextFieldFocused: FocusState<Bool>.Binding
    let isTextMode: Bool
    let canSend: Bool
    let isRequestingReply: Bool
    let loadingText: String
    let quickActions: [QuickAction]
    let attachmentActions: [AttachmentAction]
    let pendingAttachments: [ChatImageAttachment]
    let onQuickActionTap: (QuickAction) -> Void
    let onPrimaryAttachmentTap: () -> Void
    let onModeButtonTap: () -> Void
    let onAttachmentTap: () -> Void
    let onAttachmentActionTap: (AttachmentAction) -> Void
    let onRemovePendingAttachment: (UUID) -> Void
    let onVoicePressBegan: () -> Void
    let onVoiceCancelPreviewChanged: (Bool) -> Void
    let onVoicePressEnded: (Bool) -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickActionsRow(actions: quickActions, onTap: onQuickActionTap)
                .accessibilityIdentifier("quick_action_scroll")

            if pendingAttachments.isEmpty == false {
                PendingAttachmentStripView(
                    attachments: pendingAttachments,
                    onRemove: onRemovePendingAttachment
                )
            }

            composerCard

            if isAttachmentDrawerPresented {
                AttachmentDrawerView(
                    actions: attachmentActions,
                    onTap: onAttachmentActionTap
                )
                    .accessibilityIdentifier("attachment_drawer")
            }
        }
    }

    private var composerCard: some View {
        HStack(spacing: 12) {
            if isTextMode == false || text.isEmpty {
                IconStripButton(
                    systemImage: "camera",
                    accessibilityIdentifier: "composer_camera_button",
                    action: onPrimaryAttachmentTap
                )
            }

            Group {
                if isTextMode {
                    TextField("发消息...", text: $text, axis: .vertical)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.86))
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                        .focused(isTextFieldFocused)
                        .onTapGesture {
                            if isAttachmentDrawerPresented {
                                isAttachmentDrawerPresented = false
                            }
                        }
                        .accessibilityIdentifier("composer_text_input")
                } else {
                    PressToTalkButton(
                        onPressBegan: onVoicePressBegan,
                        onCancelPreviewChanged: onVoiceCancelPreviewChanged,
                        onPressEnded: onVoicePressEnded
                    )
                        .accessibilityIdentifier("composer_voice_button")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isRequestingReply {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Color(red: 0.09, green: 0.48, blue: 1.0))

                    Text(loadingText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.44))
                }
                .padding(.trailing, 2)
                .accessibilityIdentifier("composer_loading_indicator")
            } else if canSend {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color(red: 0.09, green: 0.48, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("发送")
                .accessibilityIdentifier("composer_send_button")
            } else {
                IconStripButton(
                    systemImage: isTextMode ? "waveform" : "keyboard",
                    accessibilityIdentifier: "composer_mode_button",
                    action: onModeButtonTap
                )

                IconStripButton(
                    systemImage: isAttachmentDrawerPresented ? "xmark" : "plus",
                    accessibilityIdentifier: "composer_plus_button",
                    action: onAttachmentTap
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

private struct QuickActionsRow: View {
    let actions: [QuickAction]
    let onTap: (QuickAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button {
                        onTap(action)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 12, weight: .semibold))

                            Text(action.title)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Color.black.opacity(0.76))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct PressToTalkButton: View {
    let onPressBegan: () -> Void
    let onCancelPreviewChanged: (Bool) -> Void
    let onPressEnded: (Bool) -> Void
    @State private var isPressing = false
    @State private var isCancellationPending = false

    private let cancelThreshold: CGFloat = -72

    var body: some View {
        Text("按住说话")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.84))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded { _ in
                        guard isPressing == false else { return }
                        isPressing = true
                        isCancellationPending = false
                        onPressBegan()
                    }
            )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
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
                onPressEnded(shouldCancel)
            }
    }
}

private struct IconStripButton: View {
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct AttachmentDrawerView: View {
    let actions: [AttachmentAction]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: max(actions.count, 1))
    }

    let onTap: (AttachmentAction) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(actions) { action in
                Button {
                    onTap(action)
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.84))
                            .frame(width: 34, height: 34)

                        Text(action.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.72))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.965, green: 0.965, blue: 0.968))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

private struct InlineToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.76))
            )
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct RecordingOverlayView: View {
    let state: VoiceInputController.CaptureState
    let transcript: String
    let sendMode: VoiceSendMode
    let isCancellationPending: Bool

    private var promptText: String {
        if isCancellationPending {
            return "松开后不会发送，也不会写入输入框。"
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTranscript.isEmpty == false else {
            if state == .recognizing {
                return "请稍等，正在整理你刚才说的话..."
            }

            return "开始说话后，文字会实时显示在这里。"
        }

        return trimmedTranscript
    }

    private var titleText: String {
        isCancellationPending ? "松开取消语音输入" : state.title
    }

    private var footerText: String {
        if isCancellationPending {
            return "上滑到取消区域后松开"
        }

        return sendMode == .auto ? "松开后自动发送" : "松开后写入输入框"
    }

    private var accentColor: Color {
        if isCancellationPending {
            return Color(red: 0.96, green: 0.28, blue: 0.33)
        }

        return Color(red: 0.09, green: 0.48, blue: 1.0)
    }

    private var secondaryAccentColor: Color {
        if isCancellationPending {
            return Color(red: 1.0, green: 0.44, blue: 0.47)
        }

        return Color(red: 0.15, green: 0.64, blue: 1.0)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: overlayIconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .accessibilityIdentifier("recording_overlay")

                Text(titleText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text(promptText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    )
                    .accessibilityIdentifier("recording_overlay_transcript")

                Text(footerText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .accessibilityIdentifier("recording_overlay_send_mode")

                HStack(spacing: 3) {
                    ForEach(0..<42, id: \.self) { index in
                        Capsule()
                            .fill(
                                Color.white.opacity(index.isMultiple(of: isCancellationPending ? 3 : 4) ? 0.96 : 0.7)
                            )
                            .frame(width: 2, height: index.isMultiple(of: 3) ? 12 : 8)
                    }
                }
            }
            .frame(maxWidth: 320)
            .padding(.bottom, 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        accentColor.opacity(0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                secondaryAccentColor,
                                accentColor.opacity(0.2)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 180
                        )
                    )
                    .frame(width: 420, height: 420)
                    .offset(y: 170)
                    .blur(radius: 6)
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var overlayIconName: String {
        if isCancellationPending {
            return "xmark.circle.fill"
        }

        return state == .recognizing ? "text.bubble.fill" : "waveform"
    }
}

private struct CameraPickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage) -> Void
        private let onDismiss: () -> Void

        init(
            onImagePicked: @escaping (UIImage) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.onImagePicked = onImagePicked
            self.onDismiss = onDismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            } else {
                onDismiss()
            }
        }
    }
}

private extension UIImage {
    func normalizedForAttachment(maxDimension: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let size = self.size
        let longestEdge = max(size.width, size.height)
        let scaleRatio = longestEdge > maxDimension ? maxDimension / longestEdge : 1
        let targetSize = CGSize(
            width: max(size.width * scaleRatio, 1),
            height: max(size.height * scaleRatio, 1)
        )

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

#Preview {
    ContentView()
}
