import SwiftUI

struct RecordingOverlayView: View {
    let state: VoiceInputController.CaptureState
    let transcript: String
    let sendMode: VoiceSendMode
    let isCancellationPending: Bool

    private var promptText: String {
        if isCancellationPending {
            return "松开后不会发送，也不会写入输入框。"
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTranscript.isEmpty == false else {
            if state == .recognizing {
                return "请稍等，正在整理你刚才说的话..."
            }

            return "开始说话后，文字会实时显示在这里。"
        }

        return trimmedTranscript
    }

    private var titleText: String {
        isCancellationPending ? "松开取消语音输入" : state.title
    }

    private var footerText: String {
        if isCancellationPending {
            return "上滑到取消区域后松开"
        }

        return sendMode == .auto ? "松开后自动发送" : "松开后写入输入框"
    }

    private var accentColor: Color {
        if isCancellationPending {
            return Color(red: 0.96, green: 0.28, blue: 0.33)
        }

        return Color(red: 0.09, green: 0.48, blue: 1.0)
    }

    private var secondaryAccentColor: Color {
        if isCancellationPending {
            return Color(red: 1.0, green: 0.44, blue: 0.47)
        }

        return Color(red: 0.15, green: 0.64, blue: 1.0)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: overlayIconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .accessibilityIdentifier("recording_overlay")

                Text(titleText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text(promptText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    )
                    .accessibilityIdentifier("recording_overlay_transcript")

                Text(footerText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .accessibilityIdentifier("recording_overlay_send_mode")

                HStack(spacing: 3) {
                    ForEach(0..<42, id: \.self) { index in
                        Capsule()
                            .fill(
                                Color.white.opacity(index.isMultiple(of: isCancellationPending ? 3 : 4) ? 0.96 : 0.7)
                            )
                            .frame(width: 2, height: index.isMultiple(of: 3) ? 12 : 8)
                    }
                }
            }
            .frame(maxWidth: 320)
            .padding(.bottom, 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        accentColor.opacity(0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                secondaryAccentColor,
                                accentColor.opacity(0.2)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 180
                        )
                    )
                    .frame(width: 420, height: 420)
                    .offset(y: 170)
                    .blur(radius: 6)
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var overlayIconName: String {
        if isCancellationPending {
            return "xmark.circle.fill"
        }

        return state == .recognizing ? "text.bubble.fill" : "waveform"
    }
}
