import SwiftUI

struct ChatMessagesView: View {
    let messages: [ChatMessage]
    let scrollToBottomRequest: Int
    let canDeleteMessages: Bool
    let playingMessageID: UUID?
    let onDeleteMessage: (ChatMessage) -> Void
    let onUserCopyTap: (ChatMessage) -> Void
    let onAssistantCopyTap: (ChatMessage) -> Void
    let onAssistantAudioTap: (ChatMessage) -> Void
    let onAssistantFavoriteTap: (ChatMessage) -> Void
    let onBackgroundTap: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
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
                                    playingMessageID: playingMessageID,
                                    onDelete: onDeleteMessage,
                                    onUserCopyTap: onUserCopyTap,
                                    onAssistantCopyTap: onAssistantCopyTap,
                                    onAssistantAudioTap: onAssistantAudioTap,
                                    onAssistantFavoriteTap: onAssistantFavoriteTap
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("chat_bottom_anchor")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(minHeight: max(proxy.size.height - 24, 0), alignment: .top)
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
    let playingMessageID: UUID?
    let onDelete: (ChatMessage) -> Void
    let onUserCopyTap: (ChatMessage) -> Void
    let onAssistantCopyTap: (ChatMessage) -> Void
    let onAssistantAudioTap: (ChatMessage) -> Void
    let onAssistantFavoriteTap: (ChatMessage) -> Void

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
                        AssistantMessageActionsView(
                            isFavorited: message.isFavorite,
                            isAudioPlaying: playingMessageID == message.id,
                            onCopyTap: { onAssistantCopyTap(message) },
                            onAudioTap: { onAssistantAudioTap(message) },
                            onFavoriteTap: { onAssistantFavoriteTap(message) }
                        )
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
            if message.role == .user,
               message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Button {
                    onUserCopyTap(message)
                } label: {
                    Label("复制内容", systemImage: "doc.on.doc")
                }
            }

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

struct ChatAttachmentThumbnailView: View {
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
    let isFavorited: Bool
    let isAudioPlaying: Bool
    let onCopyTap: () -> Void
    let onAudioTap: () -> Void
    let onFavoriteTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(
                systemImage: "doc.on.doc",
                accessibilityLabel: "复制消息",
                accessibilityIdentifier: "assistant_message_copy_button"
            ) { onCopyTap() }

            actionButton(
                systemImage: isAudioPlaying ? "stop.fill" : "speaker.wave.2.fill",
                accessibilityLabel: isAudioPlaying ? "停止朗读消息" : "朗读消息",
                accessibilityIdentifier: "assistant_message_audio_button",
                action: onAudioTap
            )

            actionButton(
                systemImage: isFavorited ? "bookmark.fill" : "bookmark",
                accessibilityLabel: isFavorited ? "取消收藏消息" : "收藏消息",
                accessibilityIdentifier: "assistant_message_bookmark_button"
            ) { onFavoriteTap() }
        }
        .padding(.leading, 2)
    }

    private func actionButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
