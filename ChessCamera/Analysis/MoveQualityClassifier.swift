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

    /// Count material points for White and Black (P=1, N=3, B=3, R=5, Q=9)
    static func materialPoints(fen: String) -> (white: Int, black: Int) {
        let boardPart = fen.split(separator: " ").first ?? ""
        var white = 0
        var black = 0
        for char in boardPart {
            switch char {
            case "Q": white += 9
            case "R": white += 5
            case "B", "N": white += 3
            case "P": white += 1
            case "q": black += 9
            case "r": black += 5
            case "b", "n": black += 3
            case "p": black += 1
            default: break
            }
        }
        return (white, black)
    }

    /// Classify a played move by how much winning chance it lost vs best.
    /// `before` / `after` are White-POV win percents (0…100).
    /// `playedByWhite` selects whose win% we care about.
    static func classify(
        winPercentBefore: Double,
        winPercentAfter: Double,
        playedByWhite: Bool,
        isBook: Bool = false,
        fenBefore: String? = nil,
        fenAfter: String? = nil
    ) -> (quality: MoveQuality, loss: Double) {
        if isBook {
            return (.book, 0)
        }

        let before = playedByWhite ? winPercentBefore : (100 - winPercentBefore)
        let after = playedByWhite ? winPercentAfter : (100 - winPercentAfter)
        let loss = max(0, before - after)

        // Check for brilliant sacrifice: sound piece sacrifice (piece lost >= 3 pts) while keeping advantage
        if let fenBefore, let fenAfter, loss < 2.0, after >= 50.0 {
            let matBefore = materialPoints(fen: fenBefore)
            let matAfter = materialPoints(fen: fenAfter)
            let netSacrifice = playedByWhite
                ? (matBefore.white - matAfter.white) - (matBefore.black - matAfter.black)
                : (matBefore.black - matAfter.black) - (matBefore.white - matAfter.white)
            if netSacrifice >= 3 {
                return (.brilliant, loss)
            }
        }

        // Missed win: was winning heavily before (>= 90%) and dropped to roughly equal/drawn (40-60%)
        if before >= 90.0 && after >= 40.0 && after <= 60.0 && loss >= 25.0 {
            return (.missedWin, loss)
        }

        let quality: MoveQuality
        switch loss {
        case ..<1.5: quality = .best
        case ..<4: quality = .excellent
        case ..<9: quality = .good
        case ..<18: quality = .inaccuracy
        case ..<28: quality = .mistake
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

    /// Calibrated estimated performance rating based on move accuracy and ply count.
    static func estimatedElo(accuracy: Double, plyCount: Int) -> Int {
        guard plyCount >= 4 else { return 1200 }
        let a = max(0, min(100, accuracy))
        let raw: Double
        if a < 25 {
            raw = 400 + a * 16
        } else if a < 50 {
            raw = 800 + (a - 25) * 16
        } else if a < 70 {
            raw = 1200 + (a - 50) * 25
        } else if a < 85 {
            raw = 1700 + (a - 70) * 35
        } else if a < 95 {
            raw = 2225 + (a - 85) * 45
        } else {
            raw = 2675 + (a - 95) * 45
        }
        let sampleAdjustment = min(1.0, Double(plyCount) / 16.0)
        let elo = 1000 * (1 - sampleAdjustment) + raw * sampleAdjustment
        return max(400, min(2900, Int((elo / 25.0).rounded() * 25)))
    }

    static func gameAccuracies(plies: [PlyAnalysis]) -> (white: Double?, black: Double?, whiteElo: Int?, blackElo: Int?) {
        var whiteLosses: [Double] = []
        var blackLosses: [Double] = []
        for ply in plies {
            if ply.plyIndex.isMultiple(of: 2) {
                whiteLosses.append(ply.winPercentLoss)
            } else {
                blackLosses.append(ply.winPercentLoss)
            }
        }
        let whiteAcc = accuracy(winPercentLosses: whiteLosses)
        let blackAcc = accuracy(winPercentLosses: blackLosses)

        let whiteElo = whiteAcc.map { estimatedElo(accuracy: $0, plyCount: whiteLosses.count) }
        let blackElo = blackAcc.map { estimatedElo(accuracy: $0, plyCount: blackLosses.count) }

        return (whiteAcc, blackAcc, whiteElo, blackElo)
    }
}
