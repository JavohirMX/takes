import SwiftUI

enum Theme {
    static let background = Color(red: 0.06, green: 0.09, blue: 0.16)      // #0F172A
    static let surface = Color(red: 0.12, green: 0.16, blue: 0.23)         // #1E293B
    static let surfaceMuted = Color(red: 0.15, green: 0.18, blue: 0.26)    // #272F42
    static let border = Color(red: 0.28, green: 0.33, blue: 0.41)          // #475569
    static let textPrimary = Color(red: 0.97, green: 0.98, blue: 0.99)     // #F8FAFC
    static let textSecondary = Color(red: 0.58, green: 0.64, blue: 0.72)   // #94A3B8
    static let textTertiary = Color(red: 0.40, green: 0.45, blue: 0.55)    // #64748B
    static let accent = Color(red: 0.13, green: 0.77, blue: 0.37)          // #22C55E
    static let onAccent = Color(red: 0.02, green: 0.18, blue: 0.09)        // #052E16
    static let caution = Color(red: 0.96, green: 0.62, blue: 0.04)         // #F59E0B
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)          // #EF4444
    static let statusRed = danger
    /// Slate fallback. Digital squares use `BoardStyle`.
    static var boardLight: Color { BoardStyle.slate.light }
    static var boardDark: Color { BoardStyle.slate.dark }
    static var lastMove: Color { BoardStyle.slate.lastMove }
    static let overlayScrim = Color.black.opacity(0.55)                    // #000000 @ 55%
}
