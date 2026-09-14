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

@Test func occupancyPriorFillsAndClearsLegalSquaresOnly() {
    let start = Occupancy.standardStart()
    var fillable = Occupancy()
    fillable.set(ChessSquare.parse("e4")!, occupied: true)
    var clearable = Occupancy()
    clearable.set(ChessSquare.parse("e2")!, occupied: true)
    let prior = OccupancyPrior(fillable: fillable, clearable: clearable)

    var captureLike = start
    captureLike.set(ChessSquare.parse("e2")!, occupied: false)
    let cleared = prior.apply(detected: captureLike, previous: start)
    #expect(!cleared.occupied(ChessSquare.parse("e2")!))
    #expect(cleared.occupied(ChessSquare.parse("a1")!))

    var rimMiss = start
    rimMiss.set(ChessSquare.parse("a1")!, occupied: false)
    let held = prior.apply(detected: rimMiss, previous: start)
    #expect(held.occupied(ChessSquare.parse("a1")!))

    var quiet = start
    quiet.set(ChessSquare.parse("e2")!, occupied: false)
    quiet.set(ChessSquare.parse("e4")!, occupied: true)
    let moved = prior.apply(detected: quiet, previous: start)
    #expect(!moved.occupied(ChessSquare.parse("e2")!))
    #expect(moved.occupied(ChessSquare.parse("e4")!))
}

@Test func occupancyPriorDropsNoisyMultiClears() {
    let start = Occupancy.standardStart()
    let prior = OccupancyPrior(fillable: .allSquares, clearable: .allSquares, maxNewClears: 2)
    var noisy = start
    noisy.set(ChessSquare.parse("a1")!, occupied: false)
    noisy.set(ChessSquare.parse("h1")!, occupied: false)
    noisy.set(ChessSquare.parse("a8")!, occupied: false)
    let result = prior.apply(detected: noisy, previous: start)
    #expect(result == start)
}

@Test func occupancyPriorAllowsCastlePlusReplyClearsAndDropsFiveNoisyClears() throws {
    let castle = try GameEngine(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    let prior = GameEngine.occupancyPrior(of: castle.board)
    let start = castle.occupancy()
    var both = start
    both.set(ChessSquare.parse("e1")!, occupied: false)
    both.set(ChessSquare.parse("h1")!, occupied: false)
    both.set(ChessSquare.parse("g1")!, occupied: true)
    both.set(ChessSquare.parse("f1")!, occupied: true)
    both.set(ChessSquare.parse("e8")!, occupied: false)
    both.set(ChessSquare.parse("e7")!, occupied: true)
    let gated = prior.apply(detected: both, previous: start)
    #expect(gated == both)

    let startEngine = GameEngine()
    let startPrior = GameEngine.occupancyPrior(of: startEngine.board)
    var noisy = startEngine.occupancy()
    for name in ["a2", "b2", "c2", "d2", "e2"] {
        noisy.set(ChessSquare.parse(name)!, occupied: false)
    }
    #expect(startPrior.apply(detected: noisy, previous: startEngine.occupancy()) == startEngine.occupancy())
}
