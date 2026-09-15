import ChessKit
import Foundation

struct VisualDelta: Equatable, Sendable {
    var previous: Occupancy
    var current: Occupancy
    var observedClasses: [ChessSquare: PieceClass]
}

enum InferenceResult: Equatable, Sendable {
    case none
    case unique([Move])
    case ambiguous([Move])
    case illegal

    var san: String? {
        if case .unique(let moves) = self, moves.count == 1 {
            return moves[0].san
        }
        return nil
    }
}

enum MoveInferrer {
    static let defaultHammingSlack = 2

    static func infer(
        delta: VisualDelta,
        board: Board,
        maxHammingSlack: Int = defaultHammingSlack,
        maxPlies: Int = 2
    ) -> InferenceResult {
        guard delta.previous != delta.current else { return .none }

        let visualHamming = delta.previous.hammingDistance(to: delta.current)
        let slack = visualHamming <= 1 ? 0 : maxHammingSlack

        let onePly = scorePly(
            on: board,
            current: delta.current,
            observedClasses: delta.observedClasses,
            slack: slack
        )
        let twoPly = maxPlies >= 2
            ? scoreTwoPly(
                on: board,
                current: delta.current,
                observedClasses: delta.observedClasses,
                slack: slack
            )
            : []

        let bestOne = onePly.map(\.distance).min() ?? Int.max
        let betterTwo = twoPly.filter { $0.distance < bestOne }
        if let bestTwo = betterTwo.map(\.distance).min() {
            var sequences = betterTwo.filter { $0.distance == bestTwo }.map(\.moves)
            sequences = disambiguateSequences(sequences, observedClasses: delta.observedClasses)
            var seen = Set<String>()
            sequences = sequences.filter { sequence in
                seen.insert(sequence.map(\.san).joined(separator: " ")).inserted
            }
            if sequences.count == 1 {
                return .unique(sequences[0])
            }
        }

        guard let bestDistance = onePly.map(\.distance).min() else {
            return .illegal
        }

        var matches = onePly.filter { $0.distance == bestDistance }.map(\.moves).compactMap(\.first)
        matches = disambiguatePromotions(matches, observedClasses: delta.observedClasses)

        switch matches.count {
        case 0:
            return .illegal
        case 1:
            return .unique([matches[0]])
        default:
            return .ambiguous(matches)
        }
    }

    static func debugSans(for result: InferenceResult, limit: Int = 3) -> String {
        switch result {
        case .unique(let moves) where moves.count > 1:
            return moves.prefix(limit).map(\.san).joined(separator: ",")
        case .ambiguous(let moves):
            let sans = moves.prefix(limit).map(\.san)
            return sans.isEmpty ? "" : "amb \(sans.joined(separator: ","))"
        default:
            return ""
        }
    }

    private struct ScoredSequence {
        var moves: [Move]
        var distance: Int
    }

    private static func scorePly(
        on board: Board,
        current: Occupancy,
        observedClasses: [ChessSquare: PieceClass],
        slack: Int
    ) -> [ScoredSequence] {
        var scored: [ScoredSequence] = []
        for (move, after) in legalExecutions(on: board, observedClasses: observedClasses) {
            let distance = GameEngine.occupancy(of: after).hammingDistance(to: current)
            if distance <= slack {
                scored.append(ScoredSequence(moves: [move], distance: distance))
            }
        }
        return scored
    }

    private static func scoreTwoPly(
        on board: Board,
        current: Occupancy,
        observedClasses: [ChessSquare: PieceClass],
        slack: Int
    ) -> [ScoredSequence] {
        var scored: [ScoredSequence] = []
        for (first, afterFirst) in legalExecutions(on: board, observedClasses: observedClasses) {
            for (second, afterSecond) in legalExecutions(on: afterFirst, observedClasses: observedClasses) {
                let distance = GameEngine.occupancy(of: afterSecond).hammingDistance(to: current)
                if distance <= slack {
                    scored.append(ScoredSequence(moves: [first, second], distance: distance))
                }
            }
        }
        return scored
    }

    private static func legalExecutions(
        on board: Board,
        observedClasses: [ChessSquare: PieceClass]
    ) -> [(move: Move, board: Board)] {
        var results: [(Move, Board)] = []
        let side = board.position.sideToMove
        for start in Square.allCases {
            guard board.position.piece(at: start)?.color == side else { continue }
            for end in board.legalMoves(forPieceAt: start) {
                var trial = board
                guard let executed = trial.move(pieceAt: start, to: end) else { continue }
                if case .promotion = trial.state {
                    let kinds = promotionKinds(destination: end, observedClasses: observedClasses)
                    for kind in kinds {
                        var promoTrial = board
                        guard let base = promoTrial.move(pieceAt: start, to: end) else { continue }
                        let completed = promoTrial.completePromotion(of: base, to: kind)
                        results.append((completed, promoTrial))
                    }
                } else {
                    results.append((executed, trial))
                }
            }
        }
        return results
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

    private static func disambiguateSequences(
        _ sequences: [[Move]],
        observedClasses: [ChessSquare: PieceClass]
    ) -> [[Move]] {
        guard let first = sequences.first,
              sequences.allSatisfy({ $0.count == first.count }) else {
            return sequences
        }
        var result = sequences
        for ply in first.indices {
            let plyMoves = result.map { $0[ply] }
            let filtered = disambiguatePromotions(plyMoves, observedClasses: observedClasses)
            if filtered.count < plyMoves.count {
                let allowed = Set(filtered.map(\.san))
                result = result.filter { allowed.contains($0[ply].san) }
            }
        }
        return result
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
