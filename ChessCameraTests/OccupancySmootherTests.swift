import Testing
@testable import ChessCamera

@Test func majorityDropsOneSquareFlicker() {
    var smoother = OccupancySmoother(windowSize: 3)
    let start = Occupancy.standardStart()
    var flicker = start
    flicker.set(ChessSquare.parse("e4")!, occupied: true)

    _ = smoother.ingest(start)
    _ = smoother.ingest(start)
    let smoothed = smoother.ingest(flicker)
    #expect(smoothed == start)
}

@Test func resetSeedsCommittedOccupancy() {
    var smoother = OccupancySmoother(windowSize: 3)
    let start = Occupancy.standardStart()
    var e4 = start
    e4.set(ChessSquare.parse("e2")!, occupied: false)
    e4.set(ChessSquare.parse("e4")!, occupied: true)
    smoother.reset(seeding: e4)
    #expect(smoother.ingest(e4) == e4)
}
