import AudioToolbox
import Foundation

/// Short gentle system beep when live capture needs Fix / Resume.
enum AttentionBeep {
    static func play() {
        ChessAudioFeedback.playAttention()
    }
}
