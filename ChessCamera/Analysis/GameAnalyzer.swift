import Foundation

/// Walks a game ply-by-ply and classifies each move using a `ChessAnalyzing` engine.
actor GameAnalyzer {
    private let engine: any ChessAnalyzing

    init(engine: any ChessAnalyzing) {
        self.engine = engine
    }

    struct Progress: Sendable {
        var completed: Int
        var total: Int
    }

    func analyze(
        sans: [String],
        fens: [String],
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async -> GameAnalysisResult {
        precondition(fens.count == sans.count + 1, "fens must include start + after each ply")

        let speed = AnalysisSettings.speed
        await engine.start(threads: speed.threads, hashMB: speed.hashMB)

        var plies: [PlyAnalysis] = []
        var evalSeries: [EvaluationScore] = [.centipawns(0)]
        let total = sans.count

        for index in sans.indices {
            let fenBefore = fens[index]
            let fenAfter = fens[index + 1]
            let playedByWhite = FenSide.toMove(fenBefore) == "w"

            let best = await engine.analyze(.replay(fen: fenBefore))
                ?? PositionAnalysis(
                    fen: fenBefore,
                    score: .centipawns(0),
                    bestMoveUCI: nil,
                    bestArrow: nil,
                    pvUCI: [],
                    depth: nil
                )

            let afterRaw = await engine.analyze(.replay(fen: fenAfter))
            let afterWhite = afterRaw?.score ?? best.score

            let wpBefore = MoveQualityClassifier.winPercent(score: best.score)
            let wpAfter = MoveQualityClassifier.winPercent(score: afterWhite)
            let classified = MoveQualityClassifier.classify(
                winPercentBefore: wpBefore,
                winPercentAfter: wpAfter,
                playedByWhite: playedByWhite
            )

            plies.append(
                PlyAnalysis(
                    plyIndex: index,
                    fenBefore: fenBefore,
                    best: best,
                    playedScore: afterWhite,
                    quality: classified.quality,
                    winPercentBefore: wpBefore,
                    winPercentAfter: wpAfter,
                    winPercentLoss: classified.loss
                )
            )
            evalSeries.append(afterWhite)
            onProgress?(Progress(completed: index + 1, total: total))
        }

        let accuracies = MoveQualityClassifier.gameAccuracies(plies: plies)
        return GameAnalysisResult(
            plies: plies,
            whiteAccuracy: accuracies.white,
            blackAccuracy: accuracies.black,
            evalSeries: evalSeries
        )
    }
}
