import AVFoundation
import Foundation

@MainActor
final class MoveSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var didConfigureSession = false

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configureSessionIfNeeded()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = preferredVoice()
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.02
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.02
        synthesizer.speak(utterance)
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        // 1. Look for English neural/premium quality voice
        if let premium = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .premium }) {
            return premium
        }
        // 2. Look for English enhanced quality voice
        if let enhanced = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .enhanced }) {
            return enhanced
        }
        // 3. System default English voice
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
