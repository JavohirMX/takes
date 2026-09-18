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
    /// Legacy default; quiet Hamming-2 moves use exact match via `slack(for:)`.
    static let defaultHammingSlack = 1

    static func slack(for visualHamming: Int, maxHammingSlack: Int = defaultHammingSlack) -> Int {
        switch visualHamming {
        case 1, 3, 4:
            return min(1, maxHammingSlack)
        case 2:
            return 0
        default:
            return 0
        }
    }

    /// Two-ply only for Hamming that can be quiet+quiet or quiet+capture.
    static func allowsTwoPly(visualHamming: Int) -> Bool {
        (3...4).contains(visualHamming)
    }

    static func infer(
        delta: VisualDelta,
        board: Board,
        maxHammingSlack: Int = defaultHammingSlack,
        maxPlies: Int = 2
    ) -> InferenceResult {
        guard delta.previous != delta.current else { return .none }

        let visualHamming = delta.previous.hammingDistance(to: delta.current)
        let matchSlack = slack(for: visualHamming, maxHammingSlack: maxHammingSlack)

        let onePly = scorePly(
            on: board,
            current: delta.current,
            observedClasses: delta.observedClasses,
            slack: matchSlack
        )
        let twoPly = maxPlies >= 2 && allowsTwoPly(visualHamming: visualHamming)
            ? scoreTwoPly(
                on: board,
                current: delta.current,
                observedClasses: delta.observedClasses,
                slack: matchSlack
            )
            : []

        let bestOne = onePly.map(\.distance).min() ?? Int.max
        let betterTwo = twoPly.filter { $0.distance < bestOne }
        if let bestTwo = betterTwo.map(\.distance).min() {
            var sequences = betterTwo.filter { $0.distance == bestTwo }.map(\.moves)
            sequences = disambiguateSequences(sequences)
            sequences = disambiguateSequencesByPieceColor(
                sequences,
                board: board,
                observedClasses: delta.observedClasses
            )
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
        matches = disambiguatePromotions(matches)
        matches = disambiguateNeighborFiles(
            matches,
            current: delta.current,
            observedClasses: delta.observedClasses
        )
        matches = disambiguateByPieceColor(
            matches,
            board: board,
            observedClasses: delta.observedClasses
        )

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
                    let kinds = promotionKinds()
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

    private static func promotionKinds() -> [Piece.Kind] {
        [.queen, .rook, .bishop, .knight]
    }

    private static func disambiguateSequences(
        _ sequences: [[Move]]
    ) -> [[Move]] {
        guard let first = sequences.first,
              sequences.allSatisfy({ $0.count == first.count }) else {
            return sequences
        }
        var result = sequences
        for ply in first.indices {
            let plyMoves = result.map { $0[ply] }
            let filtered = disambiguatePromotions(plyMoves)
            if filtered.count < plyMoves.count {
                let allowed = Set(filtered.map(\.san))
                result = result.filter { allowed.contains($0[ply].san) }
            }
        }
        return result
    }

    private static func disambiguatePromotions(
        _ matches: [Move]
    ) -> [Move] {
        let promotions = matches.filter { $0.promotedPiece != nil }
        guard promotions.count > 1, promotions.count == matches.count else {
            return matches
        }
        if let queen = promotions.first(where: { $0.promotedPiece?.kind == .queen }) {
            return [queen]
        }
        return promotions
    }

    /// Drop neighbor-file ghosts: a pawn on e4 beats f4, and an emptied origin
    /// beats a destination that appeared without leaving its source square.
    private static func disambiguateNeighborFiles(
        _ matches: [Move],
        current: Occupancy,
        observedClasses: [ChessSquare: PieceClass]
    ) -> [Move] {
        guard matches.count > 1 else { return matches }

        let labeled = matches.filter { move in
            guard let dest = ChessSquare.parse(move.end.notation) else { return false }
            if let observed = observedClasses[dest], observed != .empty {
                return true
            }
            return false
        }
        if labeled.count == 1 {
            return labeled
        }
        let pool = labeled.count > 1 ? labeled : matches

        let originEmpty = pool.filter { move in
            guard let from = ChessSquare.parse(move.start.notation),
                  let to = ChessSquare.parse(move.end.notation) else { return false }
            return !current.occupied(from) && current.occupied(to)
        }
        if originEmpty.count == 1 {
            return originEmpty
        }
        let afterOriginEmpty = (!originEmpty.isEmpty && originEmpty.count < pool.count) ? originEmpty : pool

        // Disambiguate by origin square presence in YOLO detections:
        // When binary occupancy has not cleared the origin yet (e.g. fusion fallback or smoother lag),
        // inspect observedClasses at candidate origins. An origin is still occupied if any piece is detected on it.
        // If candidate origins still have detected pieces while one origin is vacant, select that move.
        let originVacated = afterOriginEmpty.filter { move in
            guard let from = ChessSquare.parse(move.start.notation) else { return true }
            if let observed = observedClasses[from], observed != .empty {
                return false
            }
            return true
        }
        if originVacated.count == 1 {
            return originVacated
        }
        if !originVacated.isEmpty, originVacated.count < afterOriginEmpty.count {
            return originVacated
        }

        return afterOriginEmpty
    }

    private static func disambiguateByPieceColor(
        _ matches: [Move],
        board: Board,
        observedClasses: [ChessSquare: PieceClass]
    ) -> [Move] {
        guard matches.count > 1 else { return matches }

        let candidates: [(item: Move, pieces: [ChessSquare: PieceClass])] = matches.compactMap { move in
            var trial = board
            guard let executed = trial.move(pieceAt: move.start, to: move.end) else { return nil }
            if let promo = move.promotedPiece {
                _ = trial.completePromotion(of: executed, to: promo.kind)
            }
            return (item: move, pieces: FenCodec.parsePieces(trial.position.fen))
        }
        guard candidates.count == matches.count else { return matches }

        let destinations = matches.compactMap { ChessSquare.parse($0.end.notation) }
        return scoreCandidatesByPieceColor(
            candidates: candidates,
            destinationSquares: destinations,
            observedClasses: observedClasses
        )
    }

    private static func disambiguateSequencesByPieceColor(
        _ sequences: [[Move]],
        board: Board,
        observedClasses: [ChessSquare: PieceClass]
    ) -> [[Move]] {
        guard sequences.count > 1 else { return sequences }

        let candidates: [(item: [Move], pieces: [ChessSquare: PieceClass])] = sequences.compactMap { seq in
            var trial = board
            for move in seq {
                guard let executed = trial.move(pieceAt: move.start, to: move.end) else { return nil }
                if let promo = move.promotedPiece {
                    _ = trial.completePromotion(of: executed, to: promo.kind)
                }
            }
            return (item: seq, pieces: FenCodec.parsePieces(trial.position.fen))
        }
        guard candidates.count == sequences.count else { return sequences }

        let destinations = sequences.compactMap { $0.last }.compactMap { ChessSquare.parse($0.end.notation) }
        return scoreCandidatesByPieceColor(
            candidates: candidates,
            destinationSquares: destinations,
            observedClasses: observedClasses
        )
    }

    private static func scoreCandidatesByPieceColor<T>(
        candidates: [(item: T, pieces: [ChessSquare: PieceClass])],
        destinationSquares: [ChessSquare],
        observedClasses: [ChessSquare: PieceClass]
    ) -> [T] {
        guard candidates.count > 1 else { return candidates.map(\.item) }

        var contestedSquares = Set<ChessSquare>()
        for file in 0..<8 {
            for rank in 0..<8 {
                let sq = ChessSquare(file: file, rank: rank)
                let colors = candidates.map { $0.pieces[sq]?.pieceColor }
                if Set(colors).count > 1 {
                    contestedSquares.insert(sq)
                }
            }
        }
        for dest in destinationSquares {
            contestedSquares.insert(dest)
        }

        let observedColors = contestedSquares.compactMap { sq -> (ChessSquare, Piece.Color)? in
            guard let color = observedClasses[sq]?.pieceColor else { return nil }
            return (sq, color)
        }
        guard !observedColors.isEmpty else { return candidates.map(\.item) }

        var scores: [(item: T, matches: Int, contradictions: Int)] = []
        for candidate in candidates {
            var matchCount = 0
            var contradictionCount = 0
            for (sq, observedColor) in observedColors {
                let expectedColor = candidate.pieces[sq]?.pieceColor
                if expectedColor == observedColor {
                    matchCount += 1
                } else if expectedColor != nil {
                    contradictionCount += 1
                }
            }
            scores.append((
                item: candidate.item,
                matches: matchCount,
                contradictions: contradictionCount
            ))
        }

        let nonContradicted = scores.filter { $0.contradictions == 0 && $0.matches > 0 }
        if nonContradicted.count == 1 {
            return [nonContradicted[0].item]
        }
        if !nonContradicted.isEmpty && nonContradicted.count < candidates.count {
            return nonContradicted.map(\.item)
        }

        return candidates.map(\.item)
    }
}
