import SwiftUI
import UIKit

struct SettingsView: View {
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
