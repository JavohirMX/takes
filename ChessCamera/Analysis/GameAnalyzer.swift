import Foundation

/// Walks a game ply-by-ply and classifies each move using a `ChessAnalyzing` engine.
actor GameAnalyzer {
    private let engine: any ChessAnalyzing

    init(engine: any ChessAnalyzing) {
        self.engine = engine
    }

    struct Progress: Sendable, Equatable {
        var completed: Int
        var total: Int
    }

    /// Analyzes each ply. Calls `onPly` after every completed ply so the UI can update progressively.
    /// Throws `CancellationError` if the task is cancelled mid-run.
    func analyze(
        sans: [String],
        fens: [String],
        onPly: (@Sendable (PlyAnalysis, [EvaluationScore], Progress) -> Void)? = nil
    ) async throws -> GameAnalysisResult {
        guard fens.count == sans.count + 1 else {
            return GameAnalysisResult.empty
        }

        let speed = AnalysisSettings.speed
        await engine.start(threads: speed.threads, hashMB: speed.hashMB)

        var plies: [PlyAnalysis] = []
        var evalSeries: [EvaluationScore] = [.centipawns(0)]
        let total = sans.count

        for index in sans.indices {
            try Task.checkCancellation()

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

            try Task.checkCancellation()

            let afterRaw = await engine.analyze(.replay(fen: fenAfter))
            let afterWhite = afterRaw?.score ?? best.score

            let wpBefore = MoveQualityClassifier.winPercent(score: best.score)
            let wpAfter = MoveQualityClassifier.winPercent(score: afterWhite)
            let isBook = OpeningDetector.isBookMove(sans: sans, at: index)
            let classified = MoveQualityClassifier.classify(
                winPercentBefore: wpBefore,
                winPercentAfter: wpAfter,
                playedByWhite: playedByWhite,
                isBook: isBook,
                fenBefore: fenBefore,
                fenAfter: fenAfter
            )

            let ply = PlyAnalysis(
                plyIndex: index,
                fenBefore: fenBefore,
                best: best,
                playedScore: afterWhite,
                quality: classified.quality,
                winPercentBefore: wpBefore,
                winPercentAfter: wpAfter,
                winPercentLoss: classified.loss
            )
            plies.append(ply)
            evalSeries.append(afterWhite)
            let progress = Progress(completed: index + 1, total: total)
            onPly?(ply, evalSeries, progress)
        }

        let accuracies = MoveQualityClassifier.gameAccuracies(plies: plies)
        return GameAnalysisResult(
            plies: plies,
            whiteAccuracy: accuracies.white,
            blackAccuracy: accuracies.black,
            whiteElo: accuracies.whiteElo,
            blackElo: accuracies.blackElo,
            evalSeries: evalSeries
        )
    }
}
