import SwiftUI

struct MoveQualitySummaryView: View {
    let result: GameAnalysisResult
    var whitePlayerName: String = "White"
    var blackPlayerName: String = "Black"
    var onSelectPly: ((Int) -> Void)? = nil

    private var whitePlies: [PlyAnalysis] {
        result.plies.filter { $0.plyIndex.isMultiple(of: 2) }
    }

    private var blackPlies: [PlyAnalysis] {
        result.plies.filter { !$0.plyIndex.isMultiple(of: 2) }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Accuracy Header
            HStack(spacing: 16) {
                accuracyPill(
                    player: whitePlayerName,
                    accuracy: result.whiteAccuracy,
                    elo: result.whiteElo,
                    isWhite: true
                )
                accuracyPill(
                    player: blackPlayerName,
                    accuracy: result.blackAccuracy,
                    elo: result.blackElo,
                    isWhite: false
                )
            }

            // Quality breakdown list
            VStack(spacing: 8) {
                ForEach(MoveQuality.allCases, id: \.self) { quality in
                    qualityRow(quality)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
    }

    private func accuracyPill(player: String, accuracy: Double?, elo: Int?, isWhite: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isWhite ? Color.white : Color.gray)
                    .frame(width: 8, height: 8)
                Text(player)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            if let acc = accuracy {
                Text(String(format: "%.1f%%", acc))
                    .font(.title3.monospaced().weight(.bold))
                    .foregroundStyle(accColor(acc))
            } else {
                Text("—")
                    .font(.title3.monospaced())
                    .foregroundStyle(Theme.textTertiary)
            }

            Text("Accuracy")
                .font(.system(size: 10).weight(.medium))
                .foregroundStyle(Theme.textTertiary)

            if let elo, AnalysisSettings.showEstimatedElo {
                Text("Est. \(elo) Elo")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func qualityRow(_ quality: MoveQuality) -> some View {
        let whiteCount = whitePlies.filter { $0.quality == quality }.count
        let blackCount = blackPlies.filter { $0.quality == quality }.count

        guard whiteCount > 0 || blackCount > 0 || quality == .blunder || quality == .mistake || quality == .best else {
            return AnyView(EmptyView())
        }

        let firstWhitePly = whitePlies.first(where: { $0.quality == quality })?.plyIndex
        let firstBlackPly = blackPlies.first(where: { $0.quality == quality })?.plyIndex

        return AnyView(
            HStack {
                // White count button
                Button {
                    if let ply = firstWhitePly {
                        onSelectPly?(ply + 1)
                    }
                } label: {
                    Text("\(whiteCount)")
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(whiteCount > 0 ? Theme.textPrimary : Theme.textTertiary)
                        .frame(width: 44, alignment: .leading)
                }
                .disabled(firstWhitePly == nil)
                .buttonStyle(.plain)

                // Quality Label + Icon
                HStack(spacing: 6) {
                    Circle()
                        .fill(quality.badgeColor)
                        .frame(width: 8, height: 8)
                    Text(quality.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if !quality.glyph.isEmpty {
                        Text(quality.glyph)
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(quality.badgeColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Black count button
                Button {
                    if let ply = firstBlackPly {
                        onSelectPly?(ply + 1)
                    }
                } label: {
                    Text("\(blackCount)")
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(blackCount > 0 ? Theme.textPrimary : Theme.textTertiary)
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(firstBlackPly == nil)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        )
    }

    private func accColor(_ acc: Double) -> Color {
        if acc >= 85 { return Color(red: 0.13, green: 0.77, blue: 0.37) }
        if acc >= 70 { return Color(red: 0.96, green: 0.62, blue: 0.04) }
        return Color(red: 0.94, green: 0.27, blue: 0.27)
    }
}
