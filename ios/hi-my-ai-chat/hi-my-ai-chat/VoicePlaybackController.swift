import AVFAudio
import Combine
import Foundation
import NaturalLanguage

@MainActor
final class VoicePlaybackController: NSObject, ObservableObject {
    @Published private(set) var playingMessageID: UUID?

    private let synthesizer = AVSpeechSynthesizer()
    private let preferredLanguageCode = Locale.preferredLanguages.first ?? "zh-CN"
    private var activeUtteranceID: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func togglePlayback(for message: ChatMessage) {
        if playingMessageID == message.id {
            stop()
        } else {
            speak(message)
        }
    }

    func stop() {
        playingMessageID = nil
        activeUtteranceID = nil

        if synthesizer.isSpeaking || synthesizer.isPaused {
            if synthesizer.stopSpeaking(at: .immediate) == false {
                deactivateAudioSession()
            }
        } else {
            deactivateAudioSession()
        }
    }

    private func speak(_ message: ChatMessage) {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        stop()
        configureAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolvedVoice(for: text)
        utterance.rate = resolvedRate(for: utterance.voice)
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.05

        activeUtteranceID = ObjectIdentifier(utterance)
        playingMessageID = message.id
        synthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resolvedVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let candidates = [
            detectedLanguageCode(for: text),
            preferredLanguageCode,
            Locale.current.identifier,
            "zh-CN",
            "en-US"
        ].compactMap { $0 }

        let availableVoices = AVSpeechSynthesisVoice.speechVoices()

        for candidate in candidates {
            if let exactVoice = AVSpeechSynthesisVoice(language: candidate) {
                return exactVoice
            }

            if let matchedVoice = availableVoices.first(where: { voice in
                voice.language.caseInsensitiveCompare(candidate) == .orderedSame
                    || voice.language.lowercased().hasPrefix(candidate.lowercased())
                    || candidate.lowercased().hasPrefix(voice.language.lowercased())
            }) {
                return matchedVoice
            }
        }

        return AVSpeechSynthesisVoice()
    }

    private func resolvedRate(for voice: AVSpeechSynthesisVoice?) -> Float {
        guard let language = voice?.language.lowercased() else {
            return 0.50
        }

        if language.hasPrefix("zh") {
            return 0.45
        }

        return 0.50
    }

    private func detectedLanguageCode(for text: String) -> String? {
        guard let dominantLanguage = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue else {
            return nil
        }

        switch dominantLanguage {
        case "zh-Hans":
            return "zh-CN"
        case "zh-Hant":
            return "zh-TW"
        default:
            return dominantLanguage
        }
    }

    private func finishPlayback(for utteranceID: ObjectIdentifier) {
        guard activeUtteranceID == utteranceID else { return }

        activeUtteranceID = nil
        playingMessageID = nil
        deactivateAudioSession()
    }
}

extension VoicePlaybackController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishPlayback(for: utteranceID)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishPlayback(for: utteranceID)
        }
    }
}
