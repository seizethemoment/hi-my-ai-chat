import SwiftUI

struct MarkdownAgentScopePickerView: View {
    @Binding var scopeMode: MarkdownAgentScopeMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MarkdownAgentScopeMode.allCases) { mode in
                Button(action: { scopeMode = mode }) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(scopeMode == mode ? Color.white : Color.black.opacity(0.58))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(scopeMode == mode ? Color(red: 0.09, green: 0.48, blue: 1.0) : Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("markdown_agent_scope_\(mode.rawValue)")
            }
        }
    }
}

struct MarkdownAgentProposalSheetView: View {
    private enum PreviewTab: String, CaseIterable, Identifiable {
        case diff
        case rendered

        var id: String { rawValue }

        var title: String {
            switch self {
            case .diff:
                return "变更"
            case .rendered:
                return "预览"
            }
        }
    }

    let pendingProposal: MarkdownAgentPendingProposal
    let onApply: () -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PreviewTab = .diff

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryCard

                Picker("预览方式", selection: $selectedTab) {
                    ForEach(PreviewTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Group {
                    switch selectedTab {
                    case .diff:
                        diffList
                    case .rendered:
                        renderedPreview
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                actionBar
            }
            .background(Color(red: 0.975, green: 0.975, blue: 0.972))
            .navigationTitle("AI 修改提案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .accessibilityIdentifier("markdown_agent_proposal_close_button")
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pendingProposal.proposal.summary)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.84))

            Text(pendingProposal.diff.stats.summaryText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.48))

            HStack(spacing: 8) {
                summaryTag(title: pendingProposal.scope.label)
                summaryTag(title: pendingProposal.proposal.scopeLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func summaryTag(title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.52))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.05))
            )
    }

    private var diffList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if pendingProposal.diff.hunks.isEmpty {
                    Text("这次提案没有产生实际变更。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.48))
                        .padding(20)
                } else {
                    ForEach(pendingProposal.diff.hunks) { hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(hunk.header)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.black.opacity(0.48))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.04))

                            ForEach(hunk.lines) { line in
                                MarkdownAgentDiffRow(line: line)
                            }
                        }
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
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        .accessibilityIdentifier("markdown_agent_diff_scroll_view")
    }

    private var renderedPreview: some View {
        ScrollView {
            StreamingRichMessageView(
                text: pendingProposal.proposal.updatedMarkdown,
                toolCalls: [],
                foreground: Color.black.opacity(0.84)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .padding(.bottom, 90)
        }
        .accessibilityIdentifier("markdown_agent_rendered_preview")
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                onDiscard()
                dismiss()
            }) {
                Text("放弃")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("markdown_agent_discard_button")

            Button(action: {
                onApply()
                dismiss()
            }) {
                Text("确认写回")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.09, green: 0.48, blue: 1.0))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("markdown_agent_apply_button")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color.white)
    }
}

struct MarkdownAgentActivityLogSheetView: View {
    let entries: [MarkdownAgentActivityEntry]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "暂无日志",
                        systemImage: "text.append",
                        description: Text("开始一次 AI 修改后，这里会记录 scope 解析、提案生成、写回和回滚。")
                    )
                } else {
                    List(entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: entry.kind))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(color(for: entry.kind))

                                Text(entry.title)
                                    .font(.system(size: 14, weight: .semibold))

                                Spacer(minLength: 8)

                                Text(timestampText(for: entry.timestamp))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.42))
                            }

                            Text(entry.detail)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.58))
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Markdown Agent 日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .accessibilityIdentifier("markdown_agent_log_close_button")
                }
            }
        }
    }

    private func timestampText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func iconName(for kind: MarkdownAgentActivityEntry.Kind) -> String {
        switch kind {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }

    private func color(for kind: MarkdownAgentActivityEntry.Kind) -> Color {
        switch kind {
        case .info:
            return Color(red: 0.17, green: 0.49, blue: 0.92)
        case .success:
            return Color(red: 0.13, green: 0.62, blue: 0.31)
        case .warning:
            return Color(red: 0.88, green: 0.52, blue: 0.14)
        case .failure:
            return Color(red: 0.82, green: 0.26, blue: 0.22)
        }
    }
}

private struct MarkdownAgentDiffRow: View {
    let line: MarkdownAgentDiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.oldLineNumber.map(String.init) ?? "·")
                .frame(width: 38, alignment: .trailing)

            Text(line.newLineNumber.map(String.init) ?? "·")
                .frame(width: 38, alignment: .trailing)

            Text(prefix + line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.kind {
        case .context:
            return "  "
        case .addition:
            return "+ "
        case .deletion:
            return "- "
        }
    }

    private var foregroundColor: Color {
        switch line.kind {
        case .context:
            return Color.black.opacity(0.72)
        case .addition:
            return Color(red: 0.12, green: 0.46, blue: 0.22)
        case .deletion:
            return Color(red: 0.77, green: 0.25, blue: 0.20)
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .context:
            return Color.clear
        case .addition:
            return Color(red: 0.90, green: 0.97, blue: 0.91)
        case .deletion:
            return Color(red: 1.0, green: 0.93, blue: 0.93)
        }
    }
}
