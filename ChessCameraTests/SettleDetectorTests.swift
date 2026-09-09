import Testing
@testable import ChessCamera

@Test func becomesDisturbedOnOccupancyChange() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock().now
    let empty = Occupancy()
    var e4 = Occupancy()
    e4.set(ChessSquare.parse("e4")!, occupied: true)
    _ = d.ingest(empty, at: t0)
    let m = d.ingest(e4, at: t0)
    #expect(m == .disturbed(since: e4))
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
