import SwiftUI

struct SidebarSearchView: View {
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
