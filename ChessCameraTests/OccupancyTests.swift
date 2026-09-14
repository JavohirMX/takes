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

@Test func occupancyFromClassesMatchesStandardStart() {
    #expect(Occupancy.from(classes: FenCodec.standardClasses()) == Occupancy.standardStart())
}

@Test func occupancyFromClassesTracksQuietPawnPush() {
    var classes = FenCodec.standardClasses()
    classes[ChessSquare.parse("e2")!] = .empty
    classes[ChessSquare.parse("e4")!] = .whitePawn
    let occ = Occupancy.from(classes: classes)
    #expect(occ.hammingDistance(to: Occupancy.standardStart()) == 2)
    #expect(!occ.occupied(ChessSquare.parse("e2")!))
    #expect(occ.occupied(ChessSquare.parse("e4")!))
}
