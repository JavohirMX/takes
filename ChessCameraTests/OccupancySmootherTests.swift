import Testing
@testable import ChessCamera

@Test func twoFrameMissOnOccupiedSquareStaysOccupied() {
    var smoother = OccupancySmoother()
    let start = Occupancy.standardStart()
    smoother.reset(seeding: start)
    var missingA1 = start
    missingA1.set(ChessSquare.parse("a1")!, occupied: false)

    _ = smoother.ingest(missingA1)
    let stillHeld = smoother.ingest(missingA1)
    #expect(stillHeld.occupied(ChessSquare.parse("a1")!))
    #expect(stillHeld == start)
}

@Test func threeFrameEmptyClearsOccupiedSquare() {
    var smoother = OccupancySmoother()
    let start = Occupancy.standardStart()
    smoother.reset(seeding: start)
    var missingA1 = start
    missingA1.set(ChessSquare.parse("a1")!, occupied: false)

    var result = Occupancy()
    for _ in 0..<3 {
        result = smoother.ingest(missingA1)
    }
    #expect(!result.occupied(ChessSquare.parse("a1")!))
}

@Test func oneFrameGhostOnEmptySquareStaysEmpty() {
    var smoother = OccupancySmoother()
    let start = Occupancy.standardStart()
    smoother.reset(seeding: start)
    var ghostE4 = start
    ghostE4.set(ChessSquare.parse("e4")!, occupied: true)

    let result = smoother.ingest(ghostE4)
    #expect(!result.occupied(ChessSquare.parse("e4")!))
    #expect(result == start)
}

@Test func twoFrameFillOccupiesEmptySquare() {
    var smoother = OccupancySmoother()
    let start = Occupancy.standardStart()
    smoother.reset(seeding: start)
    var e4 = start
    e4.set(ChessSquare.parse("e4")!, occupied: true)

    _ = smoother.ingest(e4)
    let result = smoother.ingest(e4)
    #expect(result.occupied(ChessSquare.parse("e4")!))
}

@Test func resetSeedsCommittedOccupancy() {
    var smoother = OccupancySmoother()
    let start = Occupancy.standardStart()
    var e4 = start
    e4.set(ChessSquare.parse("e2")!, occupied: false)
    e4.set(ChessSquare.parse("e4")!, occupied: true)
    smoother.reset(seeding: e4)
    #expect(smoother.ingest(e4) == e4)
}
