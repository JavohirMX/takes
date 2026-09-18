import ChessKit
import Foundation

/// Formats engine UCI Principal Variation (PV) moves into human-readable numbered SAN lines.
enum PVFormatter {
    /// Format engine UCI PV moves (e.g. `["e7e5", "g1f3", "b8c6"]`) from a starting FEN into numbered SAN string (e.g. `1... e5 2. Nf3 Nc6`).
    static func format(fen: String, uciMoves: [String], maxMoves: Int = 6) -> String {
        guard !uciMoves.isEmpty else { return "" }
        guard let position = Position(fen: fen) else {
            return uciMoves.prefix(maxMoves).joined(separator: " ")
        }

        var currentBoard = Board(position: position)
        var formattedParts: [String] = []

        let parts = fen.split(separator: " ")
        let isInitialWhite = parts.count > 1 ? (parts[1] == "w") : true
        var fullmoveNumber = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1
        var isWhiteTurn = isInitialWhite

        for (index, uci) in uciMoves.prefix(maxMoves).enumerated() {
            guard let parsed = UCIMove.parse(uci) else { break }
            let fromNotation = parsed.from.algebraic
            let toNotation = parsed.to.algebraic

            guard let start = Square.allCases.first(where: { $0.notation == fromNotation }),
                  let end = Square.allCases.first(where: { $0.notation == toNotation }) else {
                break
            }

            var trial = currentBoard
            guard let executed = trial.move(pieceAt: start, to: end) else {
                break
            }

            var committed = executed
            if case .promotion(let pending) = trial.state {
                let promoKind: Piece.Kind = {
                    switch parsed.promotion {
                    case "r": return .rook
                    case "b": return .bishop
                    case "n": return .knight
                    default: return .queen
                    }
                }()
                committed = trial.completePromotion(of: pending, to: promoKind)
            }

            currentBoard = trial
            let san = committed.san

            if isWhiteTurn {
                formattedParts.append("\(fullmoveNumber). \(san)")
            } else if index == 0 {
                formattedParts.append("\(fullmoveNumber)... \(san)")
            } else {
                formattedParts.append(san)
            }

            if !isWhiteTurn {
                fullmoveNumber += 1
            }
            isWhiteTurn.toggle()
        }

        if formattedParts.isEmpty {
            return uciMoves.prefix(maxMoves).joined(separator: " ")
        }
        return formattedParts.joined(separator: " ")
    }
}
