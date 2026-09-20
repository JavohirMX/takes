import SwiftUI

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

    var body: some View {
        VStack(spacing: 16) {
            // Header: Branding & Date
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text("TAKES")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Players & Outcome
            VStack(spacing: 6) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.white).frame(width: 8, height: 8)
                            Text(whitePlayer ?? "White")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if let elo = whiteElo {
                            Text("Est. \(elo)")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(Theme.accent)
                        }
                        if let acc = whiteAccuracy {
                            Text(String(format: "%.1f%% acc", acc))
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Spacer()

                    Text(result)
                        .font(.title2.monospaced().weight(.black))
                        .foregroundStyle(resultColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(resultColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(blackPlayer ?? "Black")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Circle().fill(Color.gray).frame(width: 8, height: 8)
                        }
                        if let elo = blackElo {
                            Text("Est. \(elo)")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(Theme.accent)
                        }
                        if let acc = blackAccuracy {
                            Text(String(format: "%.1f%% acc", acc))
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                if let opening, !opening.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                        Text(opening)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .padding(.top, 4)
                }
            }

            // Digital Board
            DigitalBoardView(
                fen: finalFen,
                showsCoordinates: true,
                styleOverride: .tournament
            )
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            }

            // Footer stats
            HStack {
                Text("\(plies) moves")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Recorded with Takes Chess Camera")
                    .font(.system(size: 10).weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.border, lineWidth: 1.5)
        }
    }

    private var resultColor: Color {
        switch result {
        case "1-0": return Theme.accent
        case "0-1": return Theme.textPrimary
        case "½-½": return Theme.textSecondary
        default: return Theme.caution
        }
    }
}
