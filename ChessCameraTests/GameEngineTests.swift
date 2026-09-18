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
