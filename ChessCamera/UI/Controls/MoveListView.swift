import SwiftUI

struct MoveListView: View {
    var sans: [String]
    var selectedPly: Int?
    /// Optional per-ply quality (same length as `sans`, or sparse via dictionary).
    var qualities: [Int: MoveQuality] = [:]
    var showsQualityLabels = false
    /// Optional per-ply think times in seconds (parallel to `sans`).
    var moveTimes: [TimeInterval]? = nil
    var initialFEN: String? = nil
    var onSelect: ((Int) -> Void)?
    /// Long-press / context menu: edit this ply (later moves will be dropped).
    var onEditPly: ((Int) -> Void)?

    private struct MoveRow: Identifiable {
        let id: Int
        let moveNumber: Int
        let label: String
        let whitePly: Int?
        let blackPly: Int?
    }

    private var moveRows: [MoveRow] {
        var startMoveNumber = 1
        var startsWithBlack = false
        if let fen = initialFEN {
            let parts = fen.split(separator: " ")
            if parts.count >= 2 {
                startsWithBlack = (parts[1] == "b")
            }
            if parts.count >= 6, let num = Int(parts[5]), num > 0 {
                startMoveNumber = num
            }
        }

        var rows: [MoveRow] = []
        var ply = 0
        var currentMove = startMoveNumber

        if startsWithBlack && ply < sans.count {
            rows.append(MoveRow(
                id: currentMove * 2,
                moveNumber: currentMove,
                label: "\(currentMove)...",
                whitePly: nil,
                blackPly: ply
            ))
            ply += 1
            currentMove += 1
        }

        while ply < sans.count {
            let white = ply
            let black = (ply + 1 < sans.count) ? ply + 1 : nil
            rows.append(MoveRow(
                id: currentMove * 2 + 1,
                moveNumber: currentMove,
                label: "\(currentMove).",
                whitePly: white,
                blackPly: black
            ))
            ply += (black != nil ? 2 : 1)
            currentMove += 1
        }

        return rows
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if sans.isEmpty {
                        Text("No moves yet")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(moveRows) { row in
                        HStack(spacing: 8) {
                            Text(row.label)
                                .font(.body.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(minWidth: 32, alignment: .trailing)
                            if let white = row.whitePly {
                                plyButton(index: white)
                            }
                            if let black = row.blackPly {
                                plyButton(index: black)
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
        let timeLabel = thinkTimeLabel(at: index)
        return Button {
            onSelect?(index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
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
                if let timeLabel {
                    Text(timeLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selected ? Theme.accent.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .frame(minHeight: 44, alignment: .leading)
        }
        .id(index)
        .disabled(onSelect == nil && onEditPly == nil)
        .contextMenu {
            if let onEditPly {
                Button {
                    onEditPly(index)
                } label: {
                    Label("Edit this move…", systemImage: "pencil")
                }
            }
        }
        .accessibilityLabel(spokenMove(index: index, san: san, quality: quality, time: timeLabel))
    }

    private func thinkTimeLabel(at index: Int) -> String? {
        guard let moveTimes, index < moveTimes.count else { return nil }
        return MoveThinkTimer.formatCompact(moveTimes[index])
    }

    private func qualityLabel(san: String, quality: MoveQuality?) -> String {
        PieceNotationFormatter.format(san: san, style: notationStyle)
    }

    private func qualityColor(_ quality: MoveQuality?) -> Color {
        guard let quality else { return Theme.textPrimary }
        return quality.badgeColor
    }

    private func spokenMove(index: Int, san: String, quality: MoveQuality? = nil, time: String? = nil) -> String {
        var startMoveNumber = 1
        var startsWithBlack = false
        if let fen = initialFEN {
            let parts = fen.split(separator: " ")
            if parts.count >= 2 {
                startsWithBlack = (parts[1] == "b")
            }
            if parts.count >= 6, let num = Int(parts[5]), num > 0 {
                startMoveNumber = num
            }
        }
        let isBlack = startsWithBlack ? (index % 2 == 0) : (index % 2 != 0)
        let offset = startsWithBlack ? (index + 1) / 2 : index / 2
        let number = startMoveNumber + offset
        let color = isBlack ? "Black" : "White"
        var base = "Move \(number), \(color), \(SANSpeech.speak(san))"
        if let quality {
            base += ", \(quality.title)"
        }
        if let time {
            base += ", \(time)"
        }
        return base
    }
}

struct RecentPlyStrip: View {
    var sans: [String]
    var initialFEN: String? = nil
    var maxPlies: Int = 6

    @AppStorage(AnalysisSettings.pieceNotationKey) private var pieceNotationRaw = PieceNotationStyle.figurines.rawValue

    private var notationStyle: PieceNotationStyle {
        PieceNotationStyle(rawValue: pieceNotationRaw) ?? .figurines
    }

    var body: some View {
        let previewText = sans.isEmpty
            ? "No moves yet"
            : PGNMoveList.preview(
                sans: sans.map { PieceNotationFormatter.format(san: $0, style: notationStyle) },
                initialFEN: initialFEN,
                maxPlies: maxPlies,
                trailing: true
            )
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
