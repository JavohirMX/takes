import Foundation

/// Parse UCI move tokens (`e2e4`, `e7e8q`) into board squares.
enum UCIMove {
    static func parse(_ uci: String) -> (from: ChessSquare, to: ChessSquare, promotion: Character?)? {
        let trimmed = uci.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 4 else { return nil }
        let fromAlgebraic = String(trimmed.prefix(2))
        let toAlgebraic = String(trimmed.dropFirst(2).prefix(2))
        guard let from = ChessSquare.parse(fromAlgebraic),
              let to = ChessSquare.parse(toAlgebraic) else { return nil }
        var promotion: Character?
        if trimmed.count >= 5 {
            let promo = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)]
            if "qrbn".contains(promo) {
                promotion = promo
            }
        }
        return (from, to, promotion)
    }

    static func arrow(from uci: String) -> BoardArrow? {
        guard let parsed = parse(uci) else { return nil }
        return BoardArrow(from: parsed.from, to: parsed.to)
    }
}

enum FenSide {
    /// `"w"` or `"b"` from a FEN string.
    static func toMove(_ fen: String) -> String {
        let parts = fen.split(separator: " ")
        guard parts.count >= 2 else { return "w" }
        return String(parts[1])
    }

    static func isWhiteToMove(_ fen: String) -> Bool {
        toMove(fen) == "w"
    }
}

extension EvaluationScore {
    /// Flip a side-to-move score to White's point of view.
    func whitePOV(sideToMoveIsWhite: Bool) -> EvaluationScore {
        guard !sideToMoveIsWhite else { return self }
        switch self {
        case .centipawns(let cp): return .centipawns(-cp)
        case .mate(let m): return .mate(-m)
        }
    }
}
