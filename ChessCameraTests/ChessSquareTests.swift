import Testing
@testable import Takes

@Test func algebraicA1() {
    #expect(ChessSquare(file: 0, rank: 0).algebraic == "a1")
}

@Test func algebraicH8() {
    #expect(ChessSquare(file: 7, rank: 7).algebraic == "h8")
}

@Test func parseA1AndH8() {
    #expect(ChessSquare.parse("a1") == ChessSquare(file: 0, rank: 0))
    #expect(ChessSquare.parse("h8") == ChessSquare(file: 7, rank: 7))
    #expect(ChessSquare.parse("z9") == nil)
}
