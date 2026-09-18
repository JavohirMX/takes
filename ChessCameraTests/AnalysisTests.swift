import Foundation
import Testing
@testable import Takes

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
    @Test func classifiesPliesFromFixtures() async throws {
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
        let result = try await analyzer.analyze(
            sans: ["e4", "e5"],
            fens: [start, afterE4, afterE5]
        )
        #expect(result.plies.count == 2)
        #expect(result.evalSeries.count == 3)
        #expect(result.whiteAccuracy != nil)
        #expect(result.blackAccuracy != nil)
        #expect(result.plies[0].quality != nil)
    }

    @Test func callsOnPlyProgressively() async throws {
        let start = FenCodec.standard
        let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let afterE5 = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
        let fake = FakeChessAnalyzer()
        let analyzer = GameAnalyzer(engine: fake)
        let box = ProgressBox()
        let result = try await analyzer.analyze(
            sans: ["e4", "e5"],
            fens: [start, afterE4, afterE5]
        ) { _, _, progress in
            box.values.append(progress.completed)
        }
        #expect(result.plies.count == 2)
        #expect(box.values == [1, 2])
    }
}

/// Collects onPly callbacks without racing detached Tasks.
final class ProgressBox: @unchecked Sendable {
    var values: [Int] = []
}

@Suite("Persisted analysis")
struct PersistedAnalysisTests {
    @Test func encodeDecodeRoundTrip() {
        let result = GameAnalysisResult(
            plies: [
                PlyAnalysis(
                    plyIndex: 0,
                    fenBefore: FenCodec.standard,
                    best: PositionAnalysis(
                        fen: FenCodec.standard,
                        score: .centipawns(30),
                        bestMoveUCI: "e2e4",
                        bestArrow: BoardArrow(
                            from: ChessSquare.parse("e2")!,
                            to: ChessSquare.parse("e4")!
                        ),
                        pvUCI: ["e2e4"],
                        depth: 8
                    ),
                    playedScore: .centipawns(25),
                    quality: .best,
                    winPercentBefore: 55,
                    winPercentAfter: 54,
                    winPercentLoss: 1
                )
            ],
            whiteAccuracy: 98,
            blackAccuracy: 97,
            evalSeries: [.centipawns(0), .centipawns(25)]
        )
        let persisted = PersistedGameAnalysis(
            schemaVersion: PersistedGameAnalysis.currentSchemaVersion,
            speedRaw: AnalysisSpeed.balanced.rawValue,
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
            result: result
        )
        let data = PersistedGameAnalysis.encode(persisted)
        #expect(data != nil)
        let decoded = PersistedGameAnalysis.decode(from: data!)
        #expect(decoded == persisted)
    }

    @Test func rejectsWrongSchemaVersion() {
        struct Wrapper: Codable {
            var schemaVersion: Int
            var speedRaw: String
            var analyzedAt: Date
            var result: GameAnalysisResult
        }
        let bad = Wrapper(
            schemaVersion: 999,
            speedRaw: "fast",
            analyzedAt: .now,
            result: .empty
        )
        let data = try! JSONEncoder().encode(bad)
        #expect(PersistedGameAnalysis.decode(from: data) == nil)
    }

    @Test func gameRecordSaveLoad() {
        let record = GameRecord(
            createdAt: .now,
            pgn: "1. e4 e5",
            finalFen: FenCodec.standard,
            title: "Test"
        )
        #expect(!record.hasCachedAnalysis)
        let persisted = PersistedGameAnalysis(
            schemaVersion: 1,
            speedRaw: "fast",
            analyzedAt: .now,
            result: .empty
        )
        record.savePersistedAnalysis(persisted)
        #expect(record.hasCachedAnalysis)
        #expect(record.loadPersistedAnalysis()?.speedRaw == "fast")
        record.clearPersistedAnalysis()
        #expect(!record.hasCachedAnalysis)
    }
}

@Suite("Live AnalysisService")
struct AnalysisServiceLiveTests {
    @Test func testStockfishAnalysisAndRestart() async throws {
        let service = AnalysisService()
        await service.start(threads: 1, hashMB: 16)
        let avail = await service.availability
        guard avail == .ready else {
            // NNUE missing in CI — skip soft.
            return
        }
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let result = await service.analyze(AnalysisRequest(fen: fen, movetimeMs: 100, threads: 1, hashMB: 16))
        #expect(result != nil)

        await service.stop()

        await service.start(threads: 1, hashMB: 16)
        let result2 = await service.analyze(AnalysisRequest(fen: fen, movetimeMs: 100, threads: 1, hashMB: 16))
        #expect(result2 != nil)

        let analyzer = GameAnalyzer(engine: service)
        let start = FenCodec.standard
        let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let afterE5 = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
        let gameResult = try await analyzer.analyze(sans: ["e4", "e5"], fens: [start, afterE4, afterE5])
        #expect(gameResult.plies.count == 2)
        #expect(gameResult.whiteAccuracy != nil)
        #expect(gameResult.blackAccuracy != nil)

        await service.stop()
    }
}
