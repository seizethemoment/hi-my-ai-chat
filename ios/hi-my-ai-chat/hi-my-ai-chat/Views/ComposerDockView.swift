import SwiftUI

struct ComposerDockView: View {
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
    let pendingDocumentAttachments: [ChatDocumentAttachment]
    let onQuickActionTap: (QuickAction) -> Void
    let onPrimaryAttachmentTap: () -> Void
    let onModeButtonTap: () -> Void
    let onAttachmentTap: () -> Void
    let onAttachmentActionTap: (AttachmentAction) -> Void
    let onRemovePendingAttachment: (UUID) -> Void
    let onRemovePendingDocument: (UUID) -> Void
    let onPendingDocumentTap: (ChatDocumentAttachment) -> Void
    let onAddDocumentTap: () -> Void
    let onVoicePressBegan: () -> Void
    let onVoiceCancelPreviewChanged: (Bool) -> Void
    let onVoicePressEnded: (Bool) -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pendingDocumentAttachments.isEmpty {
                QuickActionsRow(actions: quickActions, onTap: onQuickActionTap)
                    .accessibilityIdentifier("quick_action_scroll")
            } else {
                PendingDocumentComposerBoardView(
                    attachments: pendingDocumentAttachments,
                    quickActions: quickActions,
                    onQuickActionTap: onQuickActionTap,
                    onRemove: onRemovePendingDocument,
                    onOpen: onPendingDocumentTap,
                    onAdd: onAddDocumentTap
                )
            }

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
                    TextField("输入问题或直接发送…", text: $text, axis: .vertical)
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

private struct PendingDocumentComposerBoardView: View {
    let attachments: [ChatDocumentAttachment]
    let quickActions: [QuickAction]
    let onQuickActionTap: (QuickAction) -> Void
    let onRemove: (UUID) -> Void
    let onOpen: (ChatDocumentAttachment) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(attachments) { attachment in
                        ChatDocumentCardView(
                            attachment: attachment,
                            width: 188,
                            minHeight: 118,
                            removeAction: { onRemove(attachment.id) },
                            tapAction: { onOpen(attachment) }
                        )
                    }

                    Button(action: onAdd) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.04))
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.36))
                            )
                            .frame(width: 116, height: 118)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pending_document_add_button")
                }
                .padding(.horizontal, 2)
            }

            QuickActionsRow(actions: quickActions, onTap: onQuickActionTap)
                .accessibilityIdentifier("quick_action_scroll")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
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
                    .accessibilityIdentifier(action.accessibilityIdentifier)
                }
            }
            .padding(.horizontal, 2)
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
    let onTap: (AttachmentAction) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: max(actions.count, 1))
    }

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
