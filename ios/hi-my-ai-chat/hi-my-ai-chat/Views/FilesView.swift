import SwiftUI

struct FilesView: View {
    let entries: [StoredChatDocumentEntry]
    let onOpenDocument: (ChatDocumentAttachment) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if entries.isEmpty {
                    emptyState
                        .padding(.top, 16)
                } else {
                    ForEach(entries) { entry in
                        StoredDocumentCard(
                            entry: entry,
                            onOpen: { onOpenDocument(entry.attachment) }
                        )
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.30))

            Text("还没有本地文件")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))

            Text("上传 Markdown 或 PDF 后，文件会保存在本地，这里可以统一查看和再次打开。")
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
    }
}

private struct StoredDocumentCard: View {
    let entry: StoredChatDocumentEntry
    let onOpen: () -> Void

    private var modifiedAtText: String {
        entry.modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.attachment.fileName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.76))
                        .lineLimit(1)

                    Text("最近修改于 \(modifiedAtText)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.34))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.10, green: 0.54, blue: 1.0))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(red: 0.94, green: 0.97, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("files_open_button_\(entry.attachment.id.uuidString)")
            }

            ChatDocumentCardView(
                attachment: entry.attachment,
                minHeight: 104,
                tapAction: onOpen
            )
            .accessibilityIdentifier("files_entry_\(entry.attachment.id.uuidString)")
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
