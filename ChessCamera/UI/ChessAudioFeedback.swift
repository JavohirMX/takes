import AudioToolbox
import Foundation

/// Provides acoustic feedback for over-the-board tabletop play where phone vibrations
/// cannot be felt through the table or stand.
enum ChessAudioFeedback {
    /// Crisp wood-like tap sound (System Sound 1104).
    private static let woodTapSoundID: SystemSoundID = 1104
    /// Heavier capture tap sound (System Sound 1105).
    private static let captureSoundID: SystemSoundID = 1105
    /// Clear resonant check alert tone (System Sound 1052).
    private static let checkSoundID: SystemSoundID = 1052
    /// Attention / Warning alert sound (System Sound 1057 - Tink).
    private static let attentionSoundID: SystemSoundID = 1057

    static func playMove() {
        guard SoundSettings.playSounds else { return }
        AudioServicesPlaySystemSound(woodTapSoundID)
    }

    static func playCapture() {
        guard SoundSettings.playSounds else { return }
        AudioServicesPlaySystemSound(captureSoundID)
    }

    static func playCheck() {
        guard SoundSettings.playSounds else { return }
        AudioServicesPlaySystemSound(checkSoundID)
    }

    static func playAttention() {
        AudioServicesPlaySystemSound(attentionSoundID)
    }
}
