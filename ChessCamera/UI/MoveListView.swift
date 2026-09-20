import SwiftUI

struct MoveListView: View {
    var sans: [String]
    var selectedPly: Int?
    /// Optional per-ply quality (same length as `sans`, or sparse via dictionary).
    var qualities: [Int: MoveQuality] = [:]
    var showsQualityLabels = false
    var onSelect: ((Int) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if sans.isEmpty {
                        Text("No moves yet")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(Array(stride(from: 0, to: sans.count, by: 2)), id: \.self) { start in
                        let number = start / 2 + 1
                        HStack(spacing: 8) {
                            Text("\(number).")
                                .font(.body.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(minWidth: 28, alignment: .trailing)
                            plyButton(index: start)
                            if start + 1 < sans.count {
                                plyButton(index: start + 1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: selectedPly) { _, ply in
                if let ply {
                    proxy.scrollTo(ply, anchor: .center)
                }
            }
        }
    }

    @AppStorage(AnalysisSettings.pieceNotationKey) private var pieceNotationRaw = PieceNotationStyle.figurines.rawValue

    private var notationStyle: PieceNotationStyle {
        PieceNotationStyle(rawValue: pieceNotationRaw) ?? .figurines
    }

    private func plyButton(index: Int) -> some View {
        let san = sans[index]
        let selected = selectedPly == index
        let quality = showsQualityLabels ? qualities[index] : nil
        let label = qualityLabel(san: san, quality: quality)
        return Button {
            onSelect?(index)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.body.monospaced())
                    .foregroundStyle(qualityColor(quality))
                if let quality, !quality.glyph.isEmpty {
                    Text(quality.glyph)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(qualityColor(quality))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selected ? Theme.accent.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .frame(minHeight: 44)
        }
        .id(index)
        .disabled(onSelect == nil)
        .accessibilityLabel(spokenMove(index: index, san: san, quality: quality))
    }

    private func qualityLabel(san: String, quality: MoveQuality?) -> String {
        PieceNotationFormatter.format(san: san, style: notationStyle)
    }

    private func qualityColor(_ quality: MoveQuality?) -> Color {
        guard let quality else { return Theme.textPrimary }
        return quality.badgeColor
    }

    private func spokenMove(index: Int, san: String, quality: MoveQuality? = nil) -> String {
        let number = index / 2 + 1
        var base = "Move \(number), \(SANSpeech.speak(san))"
        if let quality {
            base += ", \(quality.title)"
        }
        return base
    }
}

struct RecentPlyStrip: View {
    var sans: [String]
    var maxPlies: Int = 6

    @AppStorage(AnalysisSettings.pieceNotationKey) private var pieceNotationRaw = PieceNotationStyle.figurines.rawValue

    private var notationStyle: PieceNotationStyle {
        PieceNotationStyle(rawValue: pieceNotationRaw) ?? .figurines
    }

    var body: some View {
        let previewText = sans.isEmpty
            ? "No moves yet"
            : PGNMoveList.preview(sans: sans.map { PieceNotationFormatter.format(san: $0, style: notationStyle) }, maxPlies: maxPlies, trailing: true)
        Text(previewText)
            .font(.body.monospaced())
            .foregroundStyle(sans.isEmpty ? Theme.textSecondary : Theme.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(previewText)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

enum SANSpeech {
    static func speak(_ san: String) -> String {
        let trimmed = san.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0 != "!" && $0 != "?" }
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("O-O-O") || trimmed.hasPrefix("0-0-0") {
            return castlePhrase("long castle", san: trimmed)
        }
        if trimmed.hasPrefix("O-O") || trimmed.hasPrefix("0-0") {
            return castlePhrase("short castle", san: trimmed)
        }

        var rest = trimmed
        var suffix = ""
        if rest.hasSuffix("#") {
            suffix = " mate"
            rest.removeLast()
        } else if rest.hasSuffix("+") {
            suffix = " check"
            rest.removeLast()
        }

        var promotion = ""
        if let eq = rest.firstIndex(of: "=") {
            let promoIndex = rest.index(after: eq)
            if promoIndex < rest.endIndex {
                promotion = " promotes to \(pieceName(rest[promoIndex]))"
            }
            rest = String(rest[..<eq])
        }

        let piece: String
        if let first = rest.first, "KQRBN".contains(first) {
            piece = pieceName(first)
            rest.removeFirst()
        } else {
            piece = "pawn"
        }

        let capture = rest.contains("x")
        rest.removeAll { $0 == "x" }

        guard rest.count >= 2 else { return piece + suffix }
        let destination = String(rest.suffix(2))
        let disambiguation = String(rest.dropLast(2))
        let verb = capture ? "takes" : "to"
        var phrase = piece
        if piece != "pawn", !disambiguation.isEmpty {
            phrase += " \(disambiguation)"
        }
        phrase += " \(verb) \(destination)"
        return phrase + promotion + suffix
    }

    private static func pieceName(_ char: Character) -> String {
        switch char {
        case "K": "king"
        case "Q": "queen"
        case "R": "rook"
        case "B": "bishop"
        case "N": "knight"
        default: "pawn"
        }
    }

    private static func castlePhrase(_ castle: String, san: String) -> String {
        if san.contains("#") { return "\(castle) mate" }
        if san.contains("+") { return "\(castle) check" }
        return castle
    }
}
