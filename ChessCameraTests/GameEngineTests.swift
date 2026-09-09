import Testing
@testable import ChessCamera

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
