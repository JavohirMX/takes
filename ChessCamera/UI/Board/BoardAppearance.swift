import SwiftUI

enum BoardStyle: String, CaseIterable, Identifiable, Sendable {
    case tournament
    case walnut
    case blue
    case slate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tournament: "Tournament"
        case .walnut: "Walnut"
        case .blue: "Blue"
        case .slate: "Slate"
        }
    }

    var light: Color {
        switch self {
        case .tournament: Color(red: 1.00, green: 1.00, blue: 0.87)       // #FFFFDD
        case .walnut: Color(red: 0.94, green: 0.85, blue: 0.71)           // #F0D9B5
        case .blue: Color(red: 0.87, green: 0.89, blue: 0.90)             // #DEE3E6
        case .slate: Color(red: 0.89, green: 0.91, blue: 0.94)            // #E2E8F0
        }
    }

    var dark: Color {
        switch self {
        case .tournament: Color(red: 0.53, green: 0.65, blue: 0.40)       // #86A666
        case .walnut: Color(red: 0.71, green: 0.53, blue: 0.39)           // #B58863
        case .blue: Color(red: 0.55, green: 0.64, blue: 0.68)             // #8CA2AD
        case .slate: Color(red: 0.28, green: 0.33, blue: 0.41)            // #475569
        }
    }

    var lastMove: Color {
        switch self {
        case .tournament: Color(red: 0.96, green: 0.76, blue: 0.18).opacity(0.42)
        case .walnut: Color(red: 0.80, green: 0.80, blue: 0.16).opacity(0.40)
        case .blue: Color(red: 0.35, green: 0.62, blue: 0.88).opacity(0.40)
        case .slate: Theme.accent.opacity(0.35)
        }
    }

    var coordinateOnLight: Color { dark.opacity(0.88) }
    var coordinateOnDark: Color { light.opacity(0.92) }
    var frame: Color { dark }
}

enum BoardAppearance {
    static let styleKey = "boardStyle"
    static let defaultStyle = BoardStyle.tournament
}
