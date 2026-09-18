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
                    isWhite: true
                )
                accuracyPill(
                    player: blackPlayerName,
                    accuracy: result.blackAccuracy,
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

    private func accuracyPill(player: String, accuracy: Double?, isWhite: Bool) -> some View {
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func qualityRow(_ quality: MoveQuality) -> some View {
        let whiteCount = whitePlies.filter { $0.quality == quality }.count
        let blackCount = blackPlies.filter { $0.quality == quality }.count

        let firstWhitePly = whitePlies.first(where: { $0.quality == quality })?.plyIndex
        let firstBlackPly = blackPlies.first(where: { $0.quality == quality })?.plyIndex

        return HStack {
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
                    .fill(qualityColor(quality))
                    .frame(width: 8, height: 8)
                Text(quality.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if !quality.glyph.isEmpty {
                    Text(quality.glyph)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(qualityColor(quality))
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
    }

    private func qualityColor(_ quality: MoveQuality) -> Color {
        switch quality {
        case .best: return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .excellent: return Color(red: 0.20, green: 0.70, blue: 0.50)
        case .good: return Theme.textSecondary
        case .inaccuracy: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .mistake: return Color(red: 0.98, green: 0.45, blue: 0.09)
        case .blunder: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }

    private func accColor(_ acc: Double) -> Color {
        if acc >= 85 { return Color(red: 0.13, green: 0.77, blue: 0.37) }
        if acc >= 70 { return Color(red: 0.96, green: 0.62, blue: 0.04) }
        return Color(red: 0.94, green: 0.27, blue: 0.27)
    }
}
