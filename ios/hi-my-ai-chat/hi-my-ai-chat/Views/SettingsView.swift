import SwiftUI
import UIKit

struct SettingsView: View {
    @Binding var isVoiceAutoSendEnabled: Bool
    @Binding var openAIAPIKey: String
    @Binding var openAIBaseURL: String
    @Binding var openAIModel: String
    let onDismiss: () -> Void

    @State private var observabilityDashboard = ChatObservabilityDashboard.empty
    @State private var isLoadingObservability = true

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
                                Text("聊天回复会读取这里配置的 API Key、Base URL 和 Model。输入后会保存在本机，下次打开仍会记住；API Key 在展示时会自动脱敏。若要使用日期、定位、实时天气、未来天气预报等工具能力，Base URL 需要兼容 OpenAI function calling。")
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

                        observabilitySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
        }
        .task {
            await loadObservability()
        }
    }

    private var observabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("模型 / Agent 可观测")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.38))

            VStack(alignment: .leading, spacing: 14) {
                Text("会记录每次助手回复的模型轮次、总耗时、首轮耗时、状态码、重试次数、token 使用、工具调用与错误信息。数据仅保存在本机，可随时刷新或清空。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.44))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    SettingsActionButton(
                        title: isLoadingObservability ? "刷新中..." : "刷新",
                        systemImage: "arrow.clockwise"
                    ) {
                        Task {
                            await loadObservability()
                        }
                    }
                    .disabled(isLoadingObservability)

                    SettingsActionButton(
                        title: "清空记录",
                        systemImage: "trash",
                        tint: Color(red: 0.84, green: 0.24, blue: 0.20)
                    ) {
                        Task {
                            await ChatObservabilityStore.shared.clear()
                            await loadObservability()
                        }
                    }
                    .disabled(observabilityDashboard.records.isEmpty || isLoadingObservability)
                }

                if isLoadingObservability {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text("正在加载观测记录")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                    .padding(.vertical, 6)
                } else if observabilityDashboard.records.isEmpty {
                    SettingsEmptyStateCard(
                        title: "还没有观测记录",
                        subtitle: "发送一条消息后，这里会出现每次 Agent 运行的耗时、轮次、token 和工具调用。"
                    )
                } else {
                    SettingsObservabilitySummaryCard(dashboard: observabilityDashboard)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("最近请求")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.82))

                        ForEach(Array(observabilityDashboard.records.prefix(20))) { record in
                            SettingsObservabilityRunCard(record: record)
                        }
                    }
                }
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

    @MainActor
    private func loadObservability() async {
        isLoadingObservability = true
        observabilityDashboard = await ChatObservabilityStore.shared.dashboard()
        isLoadingObservability = false
    }
}

private struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    var tint = Color(red: 0.10, green: 0.54, blue: 1.0)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsEmptyStateCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SettingsObservabilitySummaryCard: View {
    let dashboard: ChatObservabilityDashboard

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var usage: ChatObservabilityUsage {
        dashboard.totalUsage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("运行概览")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                SettingsMetricTile(
                    title: "请求总数",
                    value: "\(dashboard.totalRuns)",
                    subtitle: "成功 \(dashboard.successCount) / 失败 \(dashboard.failureCount)"
                )
                SettingsMetricTile(
                    title: "成功率",
                    value: dashboard.successRate.map(Self.percentText(for:)) ?? "--",
                    subtitle: "已排除取消请求"
                )
                SettingsMetricTile(
                    title: "平均耗时",
                    value: dashboard.averageLatencyMilliseconds.map(Self.millisecondsText(for:)) ?? "--",
                    subtitle: "P95 \(dashboard.p95LatencyMilliseconds.map(Self.millisecondsText(for:)) ?? "--")"
                )
                SettingsMetricTile(
                    title: "平均轮次",
                    value: dashboard.averageRounds.map { String(format: "%.1f", $0) } ?? "--",
                    subtitle: "每次 Agent 运行的模型轮次"
                )
                SettingsMetricTile(
                    title: "工具调用",
                    value: "\(dashboard.totalToolCalls)",
                    subtitle: dashboard.toolFailureRate.map { "失败率 \(Self.percentText(for: $0))" } ?? "暂无工具调用"
                )
                SettingsMetricTile(
                    title: "累计 Tokens",
                    value: usage.totalTokens.map(String.init) ?? "--",
                    subtitle: tokenSummaryText(for: usage)
                )
            }

            if dashboard.topToolNames.isEmpty == false {
                Text("高频工具：\(dashboard.topToolNames.joined(separator: " · "))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func tokenSummaryText(for usage: ChatObservabilityUsage) -> String {
        let promptText = usage.promptTokens.map { "P \($0)" } ?? "P --"
        let completionText = usage.completionTokens.map { "C \($0)" } ?? "C --"
        let cachedText = usage.cachedPromptTokens.map { "缓存 \($0)" } ?? "缓存 --"
        let reasoningText = usage.reasoningTokens.map { "推理 \($0)" } ?? "推理 --"
        return [promptText, completionText, cachedText, reasoningText].joined(separator: " · ")
    }

    nonisolated private static func millisecondsText(for value: Int) -> String {
        "\(value) ms"
    }

    nonisolated private static func percentText(for value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct SettingsMetricTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.38))

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.40))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SettingsObservabilityRunCard: View {
    let record: ChatObservabilityRunRecord

    @State private var isExpanded = false

    private var statusTint: Color {
        switch record.status {
        case .success:
            return Color(red: 0.17, green: 0.62, blue: 0.33)
        case .failure:
            return Color(red: 0.84, green: 0.24, blue: 0.20)
        case .cancelled:
            return Color.black.opacity(0.38)
        }
    }

    private var statusText: String {
        switch record.status {
        case .success:
            return "成功"
        case .failure:
            return "失败"
        case .cancelled:
            return "取消"
        }
    }

    private var startedAtText: String {
        record.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var tokenText: String {
        record.usage.totalTokens.map(String.init) ?? "--"
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                metricsRow

                if let errorDescription = record.errorDescription,
                   errorDescription.isEmpty == false {
                    Text("错误：\(errorDescription)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.76, green: 0.24, blue: 0.20))
                        .fixedSize(horizontal: false, vertical: true)
                }

                detailLine(
                    title: "上下文",
                    value: "\(record.conversationTurnCount) 轮对话 · 请求 \(record.requestTurnCount) 条 · 输入 \(record.inputCharacterCount) 字 · \(record.inputImageCount) 图"
                )
                detailLine(
                    title: "耗时",
                    value: "总计 \(record.totalDurationMilliseconds) ms · 首轮 \(record.firstResponseMilliseconds.map { "\($0) ms" } ?? "--") · 模型 \(record.modelDurationMilliseconds) ms · 工具 \(record.toolDurationMilliseconds) ms · 重试 \(record.retryCount)"
                )
                detailLine(
                    title: "Usage",
                    value: usageText(for: record.usage)
                )

                if record.rounds.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("模型轮次")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.56))

                        ForEach(record.rounds) { round in
                            detailLine(
                                title: "#\(round.roundIndex)",
                                value: roundSummaryText(for: round)
                            )
                        }
                    }
                }

                if record.toolCalls.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("工具调用")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.56))

                        ForEach(record.toolCalls) { toolCall in
                            detailLine(
                                title: toolCall.name,
                                value: toolSummaryText(for: toolCall)
                            )
                        }
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 9, height: 9)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.latestUserMessagePreview)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .lineLimit(2)

                        Text("\(statusText) · \(record.model) @ \(record.baseURLHost)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 10)

                    Text(startedAtText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .multilineTextAlignment(.trailing)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(text: "\(record.totalDurationMilliseconds) ms")
                        chip(text: "\(record.rounds.count) 轮")
                        chip(text: "Tokens \(tokenText)")
                        chip(text: "\(record.toolCalls.count) 工具")
                    }
                }
            }
        }
        .tint(Color.black.opacity(0.66))
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.972, green: 0.976, blue: 0.982))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var metricsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(text: "状态码 \(record.lastStatusCode.map(String.init) ?? "--")")
                chip(text: "Finish \(record.finalFinishReason ?? "--")")
                chip(text: "X-Req \(record.lastXRequestID ?? "--")")
            }
        }
    }

    private func detailLine(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.52))
                .frame(width: 42, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.44))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.46))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white)
            )
    }

    private func usageText(for usage: ChatObservabilityUsage) -> String {
        [
            "prompt \(usage.promptTokens.map(String.init) ?? "--")",
            "completion \(usage.completionTokens.map(String.init) ?? "--")",
            "total \(usage.totalTokens.map(String.init) ?? "--")",
            "cached \(usage.cachedPromptTokens.map(String.init) ?? "--")",
            "reasoning \(usage.reasoningTokens.map(String.init) ?? "--")"
        ]
        .joined(separator: " · ")
    }

    private func roundSummaryText(for round: ChatObservabilityModelRoundRecord) -> String {
        var segments = [
            "\(round.durationMilliseconds) ms",
            "状态码 \(round.statusCode.map(String.init) ?? "--")",
            "Finish \(round.finishReason ?? "--")",
            "Tools \(round.toolCallCount)",
            "Chars \(round.responseCharacterCount)"
        ]

        if round.usage.hasAnyValue {
            segments.append("Tokens \(round.usage.totalTokens.map(String.init) ?? "--")")
        }

        if let errorDescription = round.errorDescription,
           errorDescription.isEmpty == false {
            segments.append("错误 \(errorDescription)")
        }

        return segments.joined(separator: " · ")
    }

    private func toolSummaryText(for toolCall: ChatObservabilityToolCallRecord) -> String {
        var segments = [
            toolCall.status == .success ? "成功" : "失败",
            "\(toolCall.durationMilliseconds) ms",
            "Args \(toolCall.argumentCharacterCount)",
            "Out \(toolCall.outputCharacterCount)"
        ]

        if let errorDescription = toolCall.errorDescription,
           errorDescription.isEmpty == false {
            segments.append(errorDescription)
        }

        return segments.joined(separator: " · ")
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
            .tint(Color.black.opacity(0.84))
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .tint(Color.black.opacity(0.84))
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
