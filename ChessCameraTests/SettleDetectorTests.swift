import Testing
@testable import ChessCamera

@Test func becomesDisturbedOnOccupancyChange() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock().now
    let empty = Occupancy()
    var two = Occupancy()
    two.set(ChessSquare.parse("e2")!, occupied: true)
    two.set(ChessSquare.parse("e4")!, occupied: true)
    _ = d.ingest(empty, at: t0)
    let m = d.ingest(two, at: t0)
    #expect(m == .disturbed(since: two))
}

@Test func returnsStableAfterDurationWithSameBits() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock().now
    var occ = Occupancy()
    occ.set(ChessSquare.parse("e4")!, occupied: true)
    _ = d.ingest(occ, at: t0)
    _ = d.ingest(occ, at: t0.advanced(by: .milliseconds(200)))
    let m = d.ingest(occ, at: t0.advanced(by: .milliseconds(600)))
    #expect(m == .stable(occ))
}

@Test func resetTimerWhenOccupancyChangesAgain() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock().now
    var e4 = Occupancy()
    e4.set(ChessSquare.parse("e4")!, occupied: true)
    var d4 = Occupancy()
    d4.set(ChessSquare.parse("d4")!, occupied: true)
    _ = d.ingest(e4, at: t0)
    _ = d.ingest(d4, at: t0.advanced(by: .milliseconds(400)))
    let stillDisturbed = d.ingest(d4, at: t0.advanced(by: .milliseconds(800)))
    #expect(stillDisturbed == .disturbed(since: d4))
    let stable = d.ingest(d4, at: t0.advanced(by: .milliseconds(1000)))
    #expect(stable == .stable(d4))
}

@Test func oneBitFlickerDoesNotRestartSettle() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600), maxHammingJitter: 1))
    let t0 = ContinuousClock().now
    var a = Occupancy.standardStart()
    var b = a
    b.set(ChessSquare.parse("e4")!, occupied: true)
    _ = d.ingest(a, at: t0)
    _ = d.ingest(b, at: t0.advanced(by: .milliseconds(100)))
    let stable = d.ingest(a, at: t0.advanced(by: .milliseconds(600)))
    #expect(stable == .stable(a))
}

@Test func quietMoveHammingRestartsSettle() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock().now
    var a = Occupancy.standardStart()
    var b = a
    b.set(ChessSquare.parse("e2")!, occupied: false)
    b.set(ChessSquare.parse("e4")!, occupied: true)
    #expect(a.hammingDistance(to: b) == 2)
    _ = d.ingest(a, at: t0)
    let disturbed = d.ingest(b, at: t0.advanced(by: .milliseconds(100)))
    #expect(disturbed == .disturbed(since: b))
    let still = d.ingest(b, at: t0.advanced(by: .milliseconds(400)))
    #expect(still == .disturbed(since: b))
    let stable = d.ingest(b, at: t0.advanced(by: .milliseconds(750)))
    #expect(stable == .stable(b))
}

@Test func quietElapsedTracksTimeSinceLastRealChange() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600), maxHammingJitter: 1))
    let t0 = ContinuousClock().now
    let start = Occupancy.standardStart()
    _ = d.ingest(start, at: t0)
    #expect(d.quietElapsed(at: t0.advanced(by: .milliseconds(250))) >= .milliseconds(250))
    var moved = start
    moved.set(ChessSquare.parse("e2")!, occupied: false)
    moved.set(ChessSquare.parse("e4")!, occupied: true)
    _ = d.ingest(moved, at: t0.advanced(by: .milliseconds(300)))
    #expect(d.quietElapsed(at: t0.advanced(by: .milliseconds(400))) < .milliseconds(200))
    #expect(d.quietElapsed(at: t0.advanced(by: .milliseconds(560))) >= .milliseconds(250))
}
