import Testing
@testable import ChessCamera

@Test func occupancyBitA1() {
    var occ = Occupancy()
    occ.set(ChessSquare(file: 0, rank: 0), occupied: true)
    #expect(occ.occupied(ChessSquare(file: 0, rank: 0)))
    #expect(occ.bits == 1)
}

@Test func occupancyHammingQuietMove() {
    var a = Occupancy.fullStandardPawnsAndPieces()
    var b = a
    b.set(ChessSquare(file: 4, rank: 1), occupied: false) // e2
    b.set(ChessSquare(file: 4, rank: 3), occupied: true)  // e4
    #expect(a.hammingDistance(to: b) == 2)
}

@Test func occupancyBitH8() {
    var occ = Occupancy()
    occ.set(ChessSquare(file: 7, rank: 7), occupied: true)
    #expect(occ.occupied(ChessSquare(file: 7, rank: 7)))
    #expect(occ.bits == UInt64(1) << 63)
}

@Test func standardStartHas32Pieces() {
    #expect(Occupancy.standardStart().bits.nonzeroBitCount == 32)
}
