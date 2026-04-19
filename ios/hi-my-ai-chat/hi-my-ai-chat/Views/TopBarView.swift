import SwiftUI

struct TopBarView: View {
    let title: String
    let subtitle: String
    let onMenuTap: () -> Void
    let onTitleTap: () -> Void
    let isTitleEnabled: Bool
    let isAudioAvailable: Bool
    let isAudioPlaying: Bool
    let onAudioTap: () -> Void

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
                    Button(action: onAudioTap) {
                        Image(systemName: isAudioPlaying ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                isAudioAvailable
                                    ? Color(red: 0.05, green: 0.45, blue: 1.0)
                                    : Color.black.opacity(0.18)
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAudioAvailable == false)
                    .accessibilityLabel(isAudioPlaying ? "停止朗读当前回复" : "朗读当前回复")
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
            .disabled(isTitleEnabled == false)
            .accessibilityIdentifier("top_title_button")
        }
        .frame(maxWidth: .infinity)
    }
}
