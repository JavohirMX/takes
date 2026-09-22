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

enum BestMoveArrowColor: String, CaseIterable, Identifiable, Sendable {
    case cyan
    case emerald
    case amber
    case coral
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cyan: "Cyan"
        case .emerald: "Emerald"
        case .amber: "Amber"
        case .coral: "Coral"
        case .purple: "Purple"
        }
    }

    var color: Color {
        switch self {
        case .cyan: Color(red: 0.10, green: 0.85, blue: 0.88)
        case .emerald: Color(red: 0.18, green: 0.82, blue: 0.44)
        case .amber: Color(red: 0.98, green: 0.76, blue: 0.22)
        case .coral: Color(red: 0.98, green: 0.38, blue: 0.35)
        case .purple: Color(red: 0.72, green: 0.45, blue: 0.98)
        }
    }
}

enum ArrowAppearance {
    static let colorKey = "bestMoveArrowColor"
    static let defaultColor = BestMoveArrowColor.cyan
}

enum MoveAnimationStyle: String, CaseIterable, Identifiable, Sendable {
    case smooth
    case jump
    case fast
    case pulse
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: "Smooth Slide"
        case .jump: "Arc Jump"
        case .fast: "Fast Slide"
        case .pulse: "Pulse Pop"
        case .none: "Instant"
        }
    }

    var subtitle: String {
        switch self {
        case .smooth: "Fluid piece translation with soft landing"
        case .jump: "Parabolic arc with lift and dynamic shadow"
        case .fast: "Quick snappy slide for rapid review"
        case .pulse: "Tactile arrival pop without sliding"
        case .none: "Immediate placement without animation"
        }
    }

    var icon: String {
        switch self {
        case .smooth: "arrow.right"
        case .jump: "arrowshape.bounce.right"
        case .fast: "hare.fill"
        case .pulse: "circle.circle.fill"
        case .none: "bolt.slash.fill"
        }
    }

    var isSlide: Bool {
        self == .smooth || self == .jump || self == .fast
    }

    var animation: Animation? {
        switch self {
        case .smooth:
            .easeInOut(duration: 0.22)
        case .jump:
            .easeInOut(duration: 0.26)
        case .fast:
            .easeOut(duration: 0.12)
        case .pulse:
            .spring(response: 0.24, dampingFraction: 0.65)
        case .none:
            nil
        }
    }
}

enum MoveAnimationAppearance {
    static let key = "moveAnimationStyle"
    static let defaultStyle = MoveAnimationStyle.smooth
}
