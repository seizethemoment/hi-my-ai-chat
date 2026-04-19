import SwiftUI

struct SidebarDrawerView: View {
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
