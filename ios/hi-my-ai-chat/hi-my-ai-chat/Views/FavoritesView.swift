import SwiftUI

struct FavoritesView: View {
    let entries: [FavoritedMessageEntry]
    let onOpenEntry: (FavoritedMessageEntry) -> Void
    let onRemoveFavorite: (FavoritedMessageEntry) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.30))

                        Text("还没有收藏的回复")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.78))

                        Text("在聊天页面点击模型回复下方的收藏按钮，收藏的内容会显示在这里。")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .padding(.top, 16)
                } else {
                    ForEach(entries) { entry in
                        FavoriteMessageCard(
                            entry: entry,
                            onOpen: { onOpenEntry(entry) },
                            onRemoveFavorite: { onRemoveFavorite(entry) }
                        )
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

private struct FavoriteMessageCard: View {
    let entry: FavoritedMessageEntry
    let onOpen: () -> Void
    let onRemoveFavorite: () -> Void

    private var favoriteTimeText: String {
        entry.favoritedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.sessionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.76))
                        .lineLimit(1)

                    Text("收藏于 \(favoriteTimeText)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.34))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button(action: onRemoveFavorite) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.10, green: 0.54, blue: 1.0))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(red: 0.94, green: 0.97, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("favorites_remove_button_\(entry.id.uuidString)")
            }

            Button(action: onOpen) {
                Text(entry.message.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorites_open_entry_\(entry.id.uuidString)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}
