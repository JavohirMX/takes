import AudioToolbox
import Foundation

/// Short gentle system beep when live capture needs Fix / Resume.
enum AttentionBeep {
    /// System sound “Tink” — brief, respects the silent switch.
    private static let tinkSoundID: SystemSoundID = 1057

    static func play() {
        AudioServicesPlaySystemSound(tinkSoundID)
    }
}
