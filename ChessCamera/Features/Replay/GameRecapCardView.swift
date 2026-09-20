import SwiftUI

enum RecapCardTheme: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case wood = "Wood"
    case emerald = "Emerald"

    var id: String { rawValue }

    var backgroundColor: Color {
        switch self {
        case .dark: Theme.background
        case .light: Color(red: 0.96, green: 0.97, blue: 0.98)
        case .wood: Color(red: 0.16, green: 0.12, blue: 0.09)
        case .emerald: Color(red: 0.04, green: 0.16, blue: 0.10)
        }
    }

    var cardSurface: Color {
        switch self {
        case .dark: Theme.surface
        case .light: Color.white
        case .wood: Color(red: 0.22, green: 0.16, blue: 0.12)
        case .emerald: Color(red: 0.06, green: 0.22, blue: 0.14)
        }
    }

    var textPrimary: Color {
        switch self {
        case .dark: Theme.textPrimary
        case .light: Color(red: 0.08, green: 0.11, blue: 0.16)
        case .wood: Color(red: 0.98, green: 0.94, blue: 0.88)
        case .emerald: Color(red: 0.94, green: 0.99, blue: 0.96)
        }
    }

    var textSecondary: Color {
        switch self {
        case .dark: Theme.textSecondary
        case .light: Color(red: 0.40, green: 0.45, blue: 0.55)
        case .wood: Color(red: 0.78, green: 0.70, blue: 0.60)
        case .emerald: Color(red: 0.65, green: 0.85, blue: 0.74)
        }
    }

    var accentColor: Color {
        switch self {
        case .dark, .light: Theme.accent
        case .wood: Color(red: 0.95, green: 0.72, blue: 0.32)
        case .emerald: Color(red: 0.20, green: 0.90, blue: 0.50)
        }
    }

    var borderColor: Color {
        switch self {
        case .dark: Theme.border.opacity(0.6)
        case .light: Color(red: 0.85, green: 0.88, blue: 0.92)
        case .wood: Color(red: 0.38, green: 0.28, blue: 0.20)
        case .emerald: Color(red: 0.15, green: 0.38, blue: 0.25)
        }
    }

    var defaultBoardStyle: BoardStyle {
        switch self {
        case .dark: .slate
        case .light: .tournament
        case .wood: .walnut
        case .emerald: .tournament
        }
    }
}

enum RecapCardFormat: String, CaseIterable, Identifiable {
    case card = "Card (4:5)"
    case square = "Square (1:1)"
    case story = "Story (9:16)"

    var id: String { rawValue }

    var dimensions: CGSize {
        switch self {
        case .card: CGSize(width: 340, height: 440)
        case .square: CGSize(width: 340, height: 340)
        case .story: CGSize(width: 340, height: 560)
        }
    }

    var boardSize: CGFloat {
        switch self {
        case .card: 220
        case .square: 170
        case .story: 230
        }
    }
}

struct GameRecapCardView: View {
    let title: String
    let whitePlayer: String?
    let blackPlayer: String?
    let opening: String?
    let result: String
    let finalFen: String
    let plies: Int
    let whiteAccuracy: Double?
    let blackAccuracy: Double?
    var whiteElo: Int? = nil
    var blackElo: Int? = nil
    let date: Date

    var theme: RecapCardTheme = .dark
    var format: RecapCardFormat = .card
    var showElo: Bool = true
    var showAccuracy: Bool = true
    var showOpening: Bool = true
    var showMoveCount: Bool = true
    var showDate: Bool = true
    var showCoordinates: Bool = true
    var showBranding: Bool = true
    var boardStyle: BoardStyle? = nil

    private var effectiveBoardStyle: BoardStyle {
        boardStyle ?? theme.defaultBoardStyle
    }

    var body: some View {
        VStack(spacing: format == .square ? 10 : 14) {
            // Header: Branding & Date
            HStack {
                if showBranding {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.viewfinder")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(theme.accentColor)
                        Text("TAKES")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
                Spacer()
                if showDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            if format == .story {
                Spacer(minLength: 4)
            }

            // Players & Outcome
            VStack(spacing: 4) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.white).frame(width: 7, height: 7)
                            Text(whitePlayer?.isEmpty == false ? whitePlayer! : "White")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                        }
                        if showElo, let elo = whiteElo {
                            Text("Est. \(elo)")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(theme.accentColor)
                        }
                        if showAccuracy, let acc = whiteAccuracy {
                            Text(String(format: "%.1f%% acc", acc))
                                .font(.caption2.monospaced())
                                .foregroundStyle(theme.textSecondary)
                        }
                    }

                    Spacer()

                    Text(result)
                        .font(.headline.monospaced().weight(.black))
                        .foregroundStyle(resultColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(resultColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(blackPlayer?.isEmpty == false ? blackPlayer! : "Black")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            Circle().fill(Color.gray).frame(width: 7, height: 7)
                        }
                        if showElo, let elo = blackElo {
                            Text("Est. \(elo)")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(theme.accentColor)
                        }
                        if showAccuracy, let acc = blackAccuracy {
                            Text(String(format: "%.1f%% acc", acc))
                                .font(.caption2.monospaced())
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }

                if showOpening, let opening, !opening.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                        Text(opening)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.accentColor.opacity(0.14), in: Capsule())
                    .padding(.top, 2)
                    .lineLimit(1)
                }
            }

            // Digital Board
            DigitalBoardView(
                fen: finalFen,
                showsCoordinates: showCoordinates,
                styleOverride: effectiveBoardStyle
            )
            .frame(width: format.boardSize, height: format.boardSize)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.borderColor, lineWidth: 1)
            }

            if format == .story {
                Spacer(minLength: 4)
            }

            // Footer stats
            HStack {
                if showMoveCount {
                    Text("\(plies) moves")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if showBranding {
                    Text("Recorded with Takes")
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(theme.textSecondary.opacity(0.8))
                }
            }
        }
        .padding(16)
        .frame(width: format.dimensions.width, height: format.dimensions.height)
        .background(theme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.borderColor, lineWidth: 1.5)
        }
    }

    private var resultColor: Color {
        switch result {
        case "1-0": return theme.accentColor
        case "0-1": return theme.textPrimary
        case "½-½": return theme.textSecondary
        default: return Theme.caution
        }
    }
}
