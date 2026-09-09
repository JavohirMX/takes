import ChessKit
import Foundation

struct VisualDelta: Equatable, Sendable {
    var previous: Occupancy
    var current: Occupancy
    var observedClasses: [ChessSquare: PieceClass]
}

enum InferenceResult: Equatable, Sendable {
    case none
    case unique(Move)
    case ambiguous([Move])
    case illegal

    var san: String? {
        if case .unique(let move) = self {
            return move.san
        }
        return nil
    }
}

enum MoveInferrer {
    static func infer(delta: VisualDelta, board: Board) -> InferenceResult {
        guard delta.previous != delta.current else { return .none }

        var matches: [Move] = []

        for start in Square.allCases {
            for end in board.legalMoves(forPieceAt: start) {
                var trial = board
                guard let executed = trial.move(pieceAt: start, to: end) else { continue }

                if case .promotion(let pending) = trial.state {
                    let kinds = promotionKinds(destination: end, observedClasses: delta.observedClasses)
                    for kind in kinds {
                        var promoTrial = board
                        guard let base = promoTrial.move(pieceAt: start, to: end) else { continue }
                        let completed = promoTrial.completePromotion(of: base, to: kind)
                        if GameEngine.occupancy(of: promoTrial) == delta.current {
                            matches.append(completed)
                        }
                    }
                } else if GameEngine.occupancy(of: trial) == delta.current {
                    matches.append(executed)
                }
            }
        }

        matches = disambiguatePromotions(matches, observedClasses: delta.observedClasses)

        switch matches.count {
        case 0:
            return .illegal
        case 1:
            return .unique(matches[0])
        default:
            return .ambiguous(matches)
        }
    }

    private static func promotionKinds(
        destination: Square,
        observedClasses: [ChessSquare: PieceClass]
    ) -> [Piece.Kind] {
        if let square = ChessSquare.parse(destination.notation),
           let observed = observedClasses[square],
           let kind = observed.promotionKind {
            return [kind]
        }
        return [.queen, .rook, .bishop, .knight]
    }

    private static func disambiguatePromotions(
        _ matches: [Move],
        observedClasses: [ChessSquare: PieceClass]
    ) -> [Move] {
        let promotions = matches.filter { $0.promotedPiece != nil }
        guard promotions.count > 1, promotions.count == matches.count else {
            return matches
        }

        let destination = promotions[0].end
        if let square = ChessSquare.parse(destination.notation),
           let observed = observedClasses[square],
           let kind = observed.promotionKind {
            let filtered = promotions.filter { $0.promotedPiece?.kind == kind }
            if !filtered.isEmpty { return filtered }
        }

        if let queen = promotions.first(where: { $0.promotedPiece?.kind == .queen }) {
            return [queen]
        }
        return promotions
    }
}

private extension PieceClass {
    var promotionKind: Piece.Kind? {
        switch self {
        case .whiteQueen, .blackQueen: .queen
        case .whiteRook, .blackRook: .rook
        case .whiteBishop, .blackBishop: .bishop
        case .whiteKnight, .blackKnight: .knight
        default: nil
        }
    }
}
