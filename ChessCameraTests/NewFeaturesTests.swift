import Foundation
import Testing
@testable import Takes

@Suite("New UI/UX Features")
struct NewFeaturesTests {
    @Test func testOpeningDetector() {
        let ruy = OpeningDetector.detect(sans: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"])
        #expect(ruy == "Ruy Lopez")

        let sicilian = OpeningDetector.detect(sans: ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "a6"])
        #expect(sicilian == "Sicilian: Najdorf")

        let french = OpeningDetector.detect(sans: ["e4", "e6", "d4", "d5"])
        #expect(french == "French Defense")

        let unknown = OpeningDetector.detect(sans: ["h4", "h5"])
        #expect(unknown == nil)
    }

    @Test func testPVFormatterWhite() {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let uci = ["e2e4", "e7e5", "g1f3"]
        let formatted = PVFormatter.format(fen: fen, uciMoves: uci)
        #expect(formatted == "1. e4 e5 2. Nf3")
    }

    @Test func testPVFormatterBlack() {
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let uci = ["e7e5", "g1f3", "b8c6"]
        let formatted = PVFormatter.format(fen: fen, uciMoves: uci)
        #expect(formatted == "1... e5 2. Nf3 Nc6")
    }

    @Test func testGameRecordMetadataAndPGN() {
        let record = GameRecord(
            createdAt: .now,
            pgn: "1. e4 e5 2. Nf3 *",
            finalFen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
            title: "Casual Blitz",
            whitePlayer: "Magnus",
            blackPlayer: "Hikaru",
            event: "Speed Chess",
            resultOverride: "1-0"
        )

        #expect(record.displayResult == "1-0")
        let pgnWithHeaders = record.pgnWithHeaders
        #expect(pgnWithHeaders.contains("[White \"Magnus\"]"))
        #expect(pgnWithHeaders.contains("[Black \"Hikaru\"]"))
        #expect(pgnWithHeaders.contains("[Result \"1-0\"]"))
        #expect(pgnWithHeaders.contains("[Event \"Speed Chess\"]"))
    }

    @Test func testFigurineNotationFormatter() {
        let sanKnight = "Nf3"
        let figurineKnight = PieceNotationFormatter.format(san: sanKnight, style: .figurines)
        #expect(figurineKnight == "♞f3")

        let sanBishopTakes = "Bxf7+"
        let figurineBishop = PieceNotationFormatter.format(san: sanBishopTakes, style: .figurines)
        #expect(figurineBishop == "♝xf7+")

        let sanQueen = "Qxd4"
        let figurineQueen = PieceNotationFormatter.format(san: sanQueen, style: .figurines)
        #expect(figurineQueen == "♛xd4")

        let lettersKnight = PieceNotationFormatter.format(san: sanKnight, style: .letters)
        #expect(lettersKnight == "Nf3")
    }

    @Test func testMoveRateLimitConfiguration() {
        let limit = MoveRateLimit.twoPerTwoSeconds
        #expect(limit.maxMoves == 2)
        #expect(limit.windowDurationSeconds == 2.0)

        let off = MoveRateLimit.off
        #expect(off.maxMoves == 999)
    }

    @Test func testEstimatedEloCalibration() {
        let grandmasterElo = MoveQualityClassifier.estimatedElo(accuracy: 98.0, plyCount: 40)
        #expect(grandmasterElo >= 2300)

        let intermediateElo = MoveQualityClassifier.estimatedElo(accuracy: 50.0, plyCount: 40)
        #expect(intermediateElo >= 1100 && intermediateElo <= 1300)

        let beginnerElo = MoveQualityClassifier.estimatedElo(accuracy: 25.0, plyCount: 40)
        #expect(beginnerElo <= 1000)

        let shortGamePenalty = MoveQualityClassifier.estimatedElo(accuracy: 99.0, plyCount: 4)
        #expect(shortGamePenalty < grandmasterElo)
    }

    @Test func testBookMoveDetection() {
        let moves = ["e4", "e5", "Nf3", "Nc6", "Bb5"]
        #expect(OpeningDetector.isBookMove(sans: moves, at: 0))
        #expect(OpeningDetector.isBookMove(sans: moves, at: 2))
        #expect(OpeningDetector.isBookMove(sans: moves, at: 4))

        let nonBookMoves = ["h4", "h5", "a4"]
        #expect(!OpeningDetector.isBookMove(sans: nonBookMoves, at: 2))
    }

    @Test func testExpandedMoveQuality() {
        let (bookQuality, _) = MoveQualityClassifier.classify(
            winPercentBefore: 50,
            winPercentAfter: 50,
            playedByWhite: true,
            isBook: true
        )
        #expect(bookQuality == .book)
        #expect(bookQuality.title == "Book")
        #expect(bookQuality.glyph == "📖")

        let (missedWinQuality, _) = MoveQualityClassifier.classify(
            winPercentBefore: 95,
            winPercentAfter: 50,
            playedByWhite: true
        )
        #expect(missedWinQuality == .missedWin)
        #expect(missedWinQuality.title == "Missed Win")
        #expect(missedWinQuality.glyph == "✕")
    }
}
