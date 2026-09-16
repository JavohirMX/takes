import Foundation

/// Lichess-style win% and move classification from engine scores.
/// Pure Swift — unit-testable without Stockfish.
enum MoveQualityClassifier {
    /// Lichess logistic: win% from White POV centipawns.
    /// https://lichess.org/page/accuracy
    static func winPercent(whitePOVCentipawns cp: Int) -> Double {
        let pawns = Double(cp) / 100.0
        return 50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * pawns * 100.0)) - 1.0)
    }

    static func winPercent(score: EvaluationScore) -> Double {
        winPercent(whitePOVCentipawns: score.approximateCentipawns)
    }

    /// Classify a played move by how much winning chance it lost vs best.
    /// `before` / `after` are White-POV win percents (0…100).
    /// `playedByWhite` selects whose win% we care about.
    static func classify(
        winPercentBefore: Double,
        winPercentAfter: Double,
        playedByWhite: Bool
    ) -> (quality: MoveQuality, loss: Double) {
        let before = playedByWhite ? winPercentBefore : (100 - winPercentBefore)
        let after = playedByWhite ? winPercentAfter : (100 - winPercentAfter)
        let loss = max(0, before - after)
        let quality: MoveQuality
        switch loss {
        case ..<2: quality = .best
        case ..<5: quality = .excellent
        case ..<10: quality = .good
        case ..<20: quality = .inaccuracy
        case ..<30: quality = .mistake
        default: quality = .blunder
        }
        return (quality, loss)
    }

    /// Lichess-style accuracy from average win% loss for one side.
    static func accuracy(winPercentLosses: [Double]) -> Double? {
        guard !winPercentLosses.isEmpty else { return nil }
        let mean = winPercentLosses.reduce(0, +) / Double(winPercentLosses.count)
        let raw = 103.1668 * exp(-0.04354 * mean) - 3.1669
        return max(0, min(100, raw))
    }

    static func gameAccuracies(plies: [PlyAnalysis]) -> (white: Double?, black: Double?) {
        var whiteLosses: [Double] = []
        var blackLosses: [Double] = []
        for ply in plies {
            if ply.plyIndex.isMultiple(of: 2) {
                whiteLosses.append(ply.winPercentLoss)
            } else {
                blackLosses.append(ply.winPercentLoss)
            }
        }
        return (accuracy(winPercentLosses: whiteLosses), accuracy(winPercentLosses: blackLosses))
    }
}
