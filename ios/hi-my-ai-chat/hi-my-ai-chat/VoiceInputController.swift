import AVFAudio
import Combine
import Foundation
import Speech

enum VoiceSendMode: String, CaseIterable, Identifiable {
    case manual
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "手动发送"
        case .auto:
            return "自动发送"
        }
    }
}

@MainActor
final class VoiceInputController: NSObject, ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case requestingPermission
        case recording
        case recognizing

        var showsOverlay: Bool {
            switch self {
            case .idle:
                return false
            case .requestingPermission, .recording, .recognizing:
                return true
            }
        }

        var title: String {
            switch self {
            case .idle:
                return ""
            case .requestingPermission:
                return "正在请求语音权限"
            case .recording:
                return "正在聆听，松开结束"
            case .recognizing:
                return "正在识别语音"
            }
        }
    }

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var finalTranscript: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var toastMessage: String?

    private let preferredLocaleIdentifier = Locale.preferredLanguages.first ?? "zh-CN"
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionSessionID = UUID()
    private var finalizeTask: Task<Void, Never>?
    private var shouldStopAfterPermission = false

    func beginCapture() {
        guard state == .idle else { return }

        shouldStopAfterPermission = false
        finalTranscript = nil
        lastErrorMessage = nil
        toastMessage = nil
        transcript = ""
        state = .requestingPermission

        Task {
            await startCapture()
        }
    }

    func endCapture() {
        if state == .requestingPermission {
            shouldStopAfterPermission = true
            return
        }

        guard state == .recording else { return }

        state = .recognizing
        stopAudioInput()
        recognitionRequest?.endAudio()
        scheduleRecognitionFallback()
    }

    func cancelCapture() {
        shouldStopAfterPermission = state == .requestingPermission
        finalizeTask?.cancel()
        finalizeTask = nil
        recognitionSessionID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioInput()
        transcript = ""
        finalTranscript = nil
        lastErrorMessage = nil
        toastMessage = nil
        state = .idle
    }

    func consumeFinalTranscript() {
        finalTranscript = nil
    }

    func consumeLastErrorMessage() {
        lastErrorMessage = nil
    }

    func consumeToastMessage() {
        toastMessage = nil
    }

    private func startCapture() async {
        do {
            try await requestPermissions()
            if shouldStopAfterPermission {
                shouldStopAfterPermission = false
                state = .idle
                return
            }

            try startRecognitionSession()
            state = .recording
        } catch {
            if shouldStopAfterPermission {
                shouldStopAfterPermission = false
                cancelCapture()
                return
            }
            finishWithError(error.localizedDescription)
        }
    }

    private func requestPermissions() async throws {
        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            throw VoiceInputError.microphoneDenied
        }

        let speechStatus = await requestSpeechPermission()
        guard speechStatus == .authorized else {
            throw VoiceInputError.speechRecognitionDenied(status: speechStatus)
        }

        if speechRecognizer == nil {
            speechRecognizer = makeSpeechRecognizer()
        }

        guard speechRecognizer != nil else {
            throw VoiceInputError.recognizerUnavailable
        }
    }

    private func makeSpeechRecognizer() -> SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale(identifier: preferredLocaleIdentifier))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
            ?? SFSpeechRecognizer()
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func startRecognitionSession() throws {
        guard let speechRecognizer else {
            throw VoiceInputError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        transcript = ""
        recognitionSessionID = UUID()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = try resolvedRecordingFormat(for: inputNode)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        let sessionID = recognitionSessionID
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                guard self.recognitionSessionID == sessionID else { return }
                self.handleRecognitionUpdate(result: result, error: error)
            }
        }
    }

    private func resolvedRecordingFormat(for inputNode: AVAudioInputNode) throws -> AVAudioFormat {
        let candidateFormats = [
            inputNode.outputFormat(forBus: 0),
            inputNode.inputFormat(forBus: 0)
        ]

        if let format = candidateFormats.first(where: { format in
            format.sampleRate > 0 && format.channelCount > 0
        }) {
            return format
        }

        throw VoiceInputError.microphoneUnavailable
    }

    private func handleRecognitionUpdate(result: SFSpeechRecognitionResult?, error: Error?) {
        guard state != .idle else { return }

        if let result {
            let recognizedText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            transcript = recognizedText

            if result.isFinal {
                finishSuccessfully(with: recognizedText)
                return
            }
        }

        if let error {
            let partialText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if partialText.isEmpty == false && state == .recognizing {
                finishSuccessfully(with: partialText)
                return
            }

            if state == .recognizing {
                finishWithNoSpeechDetected()
                return
            }

            finishWithError(normalizedErrorMessage(for: error))
        }
    }

    private func scheduleRecognitionFallback() {
        finalizeTask?.cancel()
        let sessionID = recognitionSessionID

        finalizeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                guard let self, self.recognitionSessionID == sessionID, self.state == .recognizing else { return }

                let partialText = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if partialText.isEmpty {
                    self.finishWithNoSpeechDetected()
                } else {
                    self.finishSuccessfully(with: partialText)
                }
            }
        }
    }

    private func finishSuccessfully(with text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            finishWithNoSpeechDetected()
            return
        }

        finalizeTask?.cancel()
        finalizeTask = nil
        finalTranscript = trimmedText
        lastErrorMessage = nil
        transcript = trimmedText
        cleanupRecognition()
        state = .idle
    }

    private func finishWithNoSpeechDetected() {
        finishWithError(VoiceInputError.noSpeechDetected.localizedDescription, presentAsToast: true)
    }

    private func finishWithError(_ message: String, presentAsToast: Bool = false) {
        finalizeTask?.cancel()
        finalizeTask = nil
        if presentAsToast {
            toastMessage = message
            lastErrorMessage = nil
        } else {
            lastErrorMessage = message
        }
        transcript = ""
        cleanupRecognition()
        state = .idle
    }

    private func cleanupRecognition() {
        recognitionSessionID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioInput()
    }

    private func stopAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func normalizedErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if message.isEmpty || message == "Retry" {
            #if targetEnvironment(simulator)
            return "模拟器当前无法稳定提供语音识别，请在真机上重试。"
            #else
            return "语音识别暂时失败，请重试。"
            #endif
        }

        return message
    }
}

private enum VoiceInputError: LocalizedError {
    case microphoneDenied
    case microphoneUnavailable
    case speechRecognitionDenied(status: SFSpeechRecognizerAuthorizationStatus)
    case recognizerUnavailable
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "没有麦克风权限，请在系统设置里允许访问麦克风。"
        case .microphoneUnavailable:
            return "当前设备没有可用的麦克风输入，无法开始语音录制。"
        case .speechRecognitionDenied:
            return "没有语音识别权限，请在系统设置里允许语音识别。"
        case .recognizerUnavailable:
            return "当前设备暂时无法使用语音识别。"
        case .noSpeechDetected:
            return "抱歉，没听到内容"
        }
    }
}
