import Foundation
import Testing
@testable import ChessCamera

@Suite("Move quality classifier")
struct MoveQualityClassifierTests {
    @Test func winPercentIsSymmetricAroundZero() {
        let even = MoveQualityClassifier.winPercent(whitePOVCentipawns: 0)
        #expect(abs(even - 50) < 0.01)
        let plus = MoveQualityClassifier.winPercent(whitePOVCentipawns: 200)
        let minus = MoveQualityClassifier.winPercent(whitePOVCentipawns: -200)
        #expect(abs((plus - 50) - (50 - minus)) < 0.5)
        #expect(plus > 50)
        #expect(minus < 50)
    }

    @Test func mateSaturatesWinPercent() {
        let mate = MoveQualityClassifier.winPercent(score: .mate(2))
        let lost = MoveQualityClassifier.winPercent(score: .mate(-2))
        #expect(mate > 95)
        #expect(lost < 5)
    }

    @Test func classifiesBlunderOnLargeDrop() {
        let (quality, loss) = MoveQualityClassifier.classify(
            winPercentBefore: 80,
            winPercentAfter: 40,
            playedByWhite: true
        )
        #expect(quality == .blunder)
        #expect(loss == 40)
    }

    @Test func classifiesBestOnTinyDrop() {
        let (quality, _) = MoveQualityClassifier.classify(
            winPercentBefore: 55,
            winPercentAfter: 54.5,
            playedByWhite: true
        )
        #expect(quality == .best)
    }

    @Test func blackLossUsesMirroredWinPercent() {
        // Before: White win% 30 → Black has 70. After: White 50 → Black 50. Loss 20.
        let (quality, loss) = MoveQualityClassifier.classify(
            winPercentBefore: 30,
            winPercentAfter: 50,
            playedByWhite: false
        )
        #expect(abs(loss - 20) < 0.01)
        #expect(quality == .mistake)
    }

    @Test func accuracyIsNilForEmpty() {
        #expect(MoveQualityClassifier.accuracy(winPercentLosses: []) == nil)
    }

    @Test func accuracyHighWhenLossesNearZero() {
        let acc = MoveQualityClassifier.accuracy(winPercentLosses: [0, 1, 0.5])
        #expect(acc != nil)
        #expect(acc! > 95)
    }
}

@Suite("UCI move parsing")
struct UCIMoveTests {
    @Test func parsesQuietMove() {
        let parsed = UCIMove.parse("e2e4")
        #expect(parsed?.from.algebraic == "e2")
        #expect(parsed?.to.algebraic == "e4")
        #expect(parsed?.promotion == nil)
    }

    @Test func parsesPromotion() {
        let parsed = UCIMove.parse("e7e8q")
        #expect(parsed?.from.algebraic == "e7")
        #expect(parsed?.to.algebraic == "e8")
        #expect(parsed?.promotion == "q")
    }

    @Test func rejectsGarbage() {
        #expect(UCIMove.parse("zz") == nil)
        #expect(UCIMove.parse("") == nil)
    }
}

@Suite("Evaluation score display")
struct EvaluationScoreTests {
    @Test func formatsCentipawns() {
        #expect(EvaluationScore.centipawns(42).display == "+0.42")
        #expect(EvaluationScore.centipawns(-150).display == "-1.50")
        #expect(EvaluationScore.centipawns(0).display == "0.00")
    }

    @Test func formatsMate() {
        #expect(EvaluationScore.mate(3).display == "M3")
        #expect(EvaluationScore.mate(-2).display == "-M2")
    }

    @Test func flipsToWhitePOV() {
        let stm = EvaluationScore.centipawns(80)
        #expect(stm.whitePOV(sideToMoveIsWhite: true) == .centipawns(80))
        #expect(stm.whitePOV(sideToMoveIsWhite: false) == .centipawns(-80))
        #expect(EvaluationScore.mate(2).whitePOV(sideToMoveIsWhite: false) == .mate(-2))
    }
}

@Suite("Game analyzer with fake engine")
struct GameAnalyzerTests {
    @Test func classifiesPliesFromFixtures() async {
        let start = FenCodec.standard
        let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let afterE5 = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"

        let fake = FakeChessAnalyzer(fixtures: [
            start: PositionAnalysis(
                fen: start,
                score: .centipawns(30),
                bestMoveUCI: "e2e4",
                bestArrow: UCIMove.arrow(from: "e2e4"),
                pvUCI: ["e2e4", "e7e5"],
                depth: 10
            ),
            afterE4: PositionAnalysis(
                fen: afterE4,
                score: .centipawns(25),
                bestMoveUCI: "e7e5",
                bestArrow: UCIMove.arrow(from: "e7e5"),
                pvUCI: ["e7e5"],
                depth: 10
            ),
            afterE5: PositionAnalysis(
                fen: afterE5,
                score: .centipawns(28),
                bestMoveUCI: "g1f3",
                bestArrow: UCIMove.arrow(from: "g1f3"),
                pvUCI: ["g1f3"],
                depth: 10
            )
        ])

        let analyzer = GameAnalyzer(engine: fake)
        let result = await analyzer.analyze(
            sans: ["e4", "e5"],
            fens: [start, afterE4, afterE5]
        )
        #expect(result.plies.count == 2)
        #expect(result.evalSeries.count == 3)
        #expect(result.whiteAccuracy != nil)
        #expect(result.blackAccuracy != nil)
        #expect(result.plies[0].quality != nil)
    }
}
