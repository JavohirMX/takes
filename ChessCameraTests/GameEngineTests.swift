import Testing
@testable import Takes

@Test func e4UpdatesFenAndPgn() throws {
    let engine = GameEngine()
    try engine.apply(san: "e4")
    #expect(engine.pgn.contains("e4"))
    #expect(engine.fen.contains("4P3"))
}

@Test func undoRestoresStart() throws {
    let engine = GameEngine()
    let start = engine.fen
    try engine.apply(san: "e4")
    try engine.undo()
    #expect(engine.fen == start)
}

@Test func castlingIsLegalFromStartAfterClearing() throws {
    let engine = try GameEngine(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    try engine.apply(san: "O-O")
    #expect(engine.occupancy().occupied(ChessSquare.parse("g1")!))
    #expect(engine.occupancy().occupied(ChessSquare.parse("f1")!))
    #expect(!engine.occupancy().occupied(ChessSquare.parse("e1")!))
    #expect(!engine.occupancy().occupied(ChessSquare.parse("h1")!))
    #expect(engine.pgn.contains("O-O"))
}

@Test func occupancyMatchesStandardStart() {
    let engine = GameEngine()
    #expect(engine.occupancy() == Occupancy.standardStart())
}

@Test func occupancyPriorAllowsE2E4AndHoldsBlockedRimRook() {
    let engine = GameEngine()
    let prior = GameEngine.occupancyPrior(of: engine.board)
    let start = engine.occupancy()
    #expect(prior.clearable.occupied(ChessSquare.parse("e2")!))
    #expect(prior.fillable.occupied(ChessSquare.parse("e4")!))
    #expect(prior.clearable.occupied(ChessSquare.parse("e7")!))
    #expect(prior.fillable.occupied(ChessSquare.parse("e5")!))
    #expect(!prior.clearable.occupied(ChessSquare.parse("a1")!))
    #expect(prior.maxNewClears == 4)

    var missA1 = start
    missA1.set(ChessSquare.parse("a1")!, occupied: false)
    #expect(prior.apply(detected: missA1, previous: start) == start)

    var e4 = start
    e4.set(ChessSquare.parse("e2")!, occupied: false)
    e4.set(ChessSquare.parse("e4")!, occupied: true)
    let gated = prior.apply(detected: e4, previous: start)
    #expect(!gated.occupied(ChessSquare.parse("e2")!))
    #expect(gated.occupied(ChessSquare.parse("e4")!))
}

@Test func occupancyPriorWithoutRepliesHidesOpponentSquares() {
    let engine = GameEngine()
    let prior = GameEngine.occupancyPrior(of: engine.board, includeReplies: false)
    #expect(prior.clearable.occupied(ChessSquare.parse("e2")!))
    #expect(prior.fillable.occupied(ChessSquare.parse("e4")!))
    #expect(!prior.clearable.occupied(ChessSquare.parse("e7")!))
    #expect(!prior.fillable.occupied(ChessSquare.parse("e5")!))
    #expect(!prior.clearable.occupied(ChessSquare.parse("a1")!))
    #expect(prior.maxNewClears == 2)
}

@Test func replaceLastPlyUpdatesPGN() throws {
    let engine = GameEngine()
    try engine.apply(san: "e4")
    try engine.apply(san: "e5")
    try engine.replaceLast(with: "c5")
    #expect(engine.pgn.contains("c5"))
    #expect(!engine.pgn.contains("e5"))
    try engine.undo()
    #expect(engine.fen.contains("4P3"))
}

@Test func fenBeforePlyMatchesPrefix() throws {
    let engine = GameEngine()
    let start = engine.fen
    try engine.apply(san: "e4")
    let afterE4 = engine.fen
    try engine.apply(san: "e5")
    try engine.apply(san: "Nf3")

    #expect(engine.fenBeforePly(0) == start)
    #expect(engine.fenBeforePly(1) == afterE4)
    #expect(engine.fenBeforePly(3) == engine.fen)
    #expect(engine.fenBeforePly(-1) == nil)
    #expect(engine.fenBeforePly(4) == nil)
}

@Test func truncateKeepsPrefixAndDropsTrailing() throws {
    let engine = GameEngine()
    try engine.apply(san: "e4")
    try engine.apply(san: "e5")
    try engine.apply(san: "Nf3")
    try engine.apply(san: "Nc6")

    try engine.truncate(toPly: 2)
    #expect(engine.plyCount == 2)
    #expect(engine.appliedSANs == ["e4", "e5"])
    #expect(engine.pgn.contains("e4"))
    #expect(engine.pgn.contains("e5"))
    #expect(!engine.pgn.contains("Nf3"))
    #expect(!engine.pgn.contains("Nc6"))
}

@Test func replaceAtPlyDropsLaterMoves() throws {
    let engine = GameEngine()
    try engine.apply(san: "e4")
    try engine.apply(san: "e5")
    try engine.apply(san: "Nf3")
    try engine.apply(san: "Nc6")

    try engine.replace(atPly: 1, with: "c5")
    #expect(engine.appliedSANs == ["e4", "c5"])
    #expect(engine.pgn.contains("c5"))
    #expect(!engine.pgn.contains("e5"))
    #expect(!engine.pgn.contains("Nf3"))
    #expect(!engine.pgn.contains("Nc6"))
}

@Test func midGameStartPreservesInitialFenAndSetsPGNTags() throws {
    let midGameFen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
    let engine = try GameEngine(fen: midGameFen)
    #expect(engine.initialFEN == midGameFen)
    #expect(engine.pgn.contains("[SetUp \"1\"]"))
    #expect(engine.pgn.contains("[FEN \"\(midGameFen)\"]"))

    try engine.apply(san: "Bb5")
    #expect(engine.appliedSANs == ["Bb5"])
    #expect(engine.initialFEN == midGameFen)
    #expect(engine.fenBeforePly(0) == midGameFen)

    // GameRecord pgnWithHeaders should also include SetUp and FEN tags
    let record = GameRecord(
        createdAt: Date(),
        pgn: engine.pgn,
        finalFen: engine.fen,
        title: "Test Game",
        initialFen: midGameFen
    )
    let headers = record.pgnWithHeaders
    #expect(headers.contains("[SetUp \"1\"]"))
    #expect(headers.contains("[FEN \"\(midGameFen)\"]"))
}

@Test func retrogradePositionSolverRecoversInitialFen() throws {
    let initialFen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
    let engine = try GameEngine(fen: initialFen)
    try engine.apply(san: "Bb5")
    try engine.apply(san: "a6")
    try engine.apply(san: "Ba4")
    let finalFen = engine.fen
    let sans = engine.appliedSANs

    let deduced = RetrogradePositionSolver.solveInitialFEN(sans: sans, finalFen: finalFen)
    #expect(deduced != nil)
    if let deduced {
        // Forward verify that applying sans from deduced produces finalFen
        let testEngine = try GameEngine(fen: deduced)
        for san in sans {
            try testEngine.apply(san: san)
        }
        #expect(testEngine.fen == finalFen)
    }
}

@Test func pgnExtractFenAndMovePreview() {
    let pgnWithFen = """
    [Event "Casual"]
    [SetUp "1"]
    [FEN "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 2 3"]

    3... Nf6 4. Nc3
    """
    let extracted = PGNMoveList.extractFEN(from: pgnWithFen)
    #expect(extracted == "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 2 3")

    let sans = ["Nf6", "Nc3", "d5"]
    let preview = PGNMoveList.preview(sans: sans, initialFEN: extracted, maxPlies: 3)
    #expect(preview.contains("3... Nf6"))
    #expect(preview.contains("4. Nc3"))
}

@Test func retrogradePositionSolverExceedsMaxNodesReturnsNilQuickly() {
    let finalFen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
    let impossibleSans = ["Rxd8+", "Kxd8", "Nxf7+", "Ke8"]
    let solved = RetrogradePositionSolver.solveInitialFEN(sans: impossibleSans, finalFen: finalFen, maxNodes: 20)
    #expect(solved == nil)
}

@Test func retrogradePositionSolverHandlesEmptySANs() {
    let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
    let solved = RetrogradePositionSolver.solveInitialFEN(sans: [], finalFen: fen)
    #expect(solved == fen)
}


