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

@Test func captureHammingDoesNotRestartSettleAndInfersFromRecording() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600), maxHammingJitter: 1))
    let t0 = ContinuousClock().now
    let start = Occupancy.standardStart()
    _ = d.ingest(start, at: t0)
    let settled = d.ingest(start, at: t0.advanced(by: .milliseconds(600)))
    #expect(settled == .stable(start))

    var capture = start
    capture.set(ChessSquare.parse("e2")!, occupied: false)
    #expect(start.hammingDistance(to: capture) == 1)
    let afterCapture = d.ingest(capture, at: t0.advanced(by: .milliseconds(700)))
    #expect(afterCapture == .stable(capture))

    let decision = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: afterCapture,
        occupancy: capture,
        commitHamming: start.hammingDistance(to: capture),
        ignored: nil
    )
    #expect(decision == .infer(capture))
    #expect(
        SessionReducer.next(phase: .recording, motion: afterCapture, inference: .none) == .recording
    )
}

@Test func liveSettleWaitsOnZeroAndHugeHamming() {
    let occ = Occupancy.standardStart()
    let stable = BoardMotion.stable(occ)
    #expect(
        LiveSettleDecision.action(
            phase: .recording,
            settleMotion: stable,
            occupancy: occ,
            commitHamming: 0,
            ignored: nil
        ) == .wait
    )
    #expect(
        LiveSettleDecision.action(
            phase: .recording,
            settleMotion: stable,
            occupancy: occ,
            commitHamming: 17,
            ignored: nil
        ) == .wait
    )
}

@Test func illegalOneBitDriftDoesNotReenterDisturbed() {
    let start = Occupancy.standardStart()
    var drift = start
    drift.set(ChessSquare.parse("e5")!, occupied: true)
    let ham = start.hammingDistance(to: drift)
    #expect(ham == 1)
    let stable = BoardMotion.stable(drift)

    let first = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: stable,
        occupancy: drift,
        commitHamming: ham,
        ignored: nil
    )
    #expect(first == .infer(drift))

    let engine = GameEngine()
    let inferred = MoveInferrer.infer(
        delta: VisualDelta(previous: start, current: drift, observedClasses: [:]),
        board: engine.board
    )
    #expect(inferred == .illegal)
    #expect(
        SessionReducer.next(phase: .recording, motion: stable, inference: .illegal) == .recording
    )

    let second = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: stable,
        occupancy: drift,
        commitHamming: ham,
        ignored: drift
    )
    #expect(second == .skipIgnored)
    #expect(
        SessionReducer.next(phase: .recording, motion: stable, inference: .none) == .recording
    )
}

@Test func captureHammingOneInfersUniqueWithoutDisturbedPhase() throws {
    let engine = try GameEngine(fen: "4k3/8/2n5/1B6/8/8/8/4K3 w - - 0 1")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("b5")!, occupied: false)
    #expect(before.hammingDistance(to: after) == 1)
    let stable = BoardMotion.stable(after)
    let decision = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: stable,
        occupancy: after,
        commitHamming: 1,
        ignored: nil
    )
    #expect(decision == .infer(after))
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    guard case .unique = result else {
        Issue.record("expected unique capture, got \(result)")
        return
    }
    #expect(result.san?.contains("Bxc6") == true)
    #expect(
        SessionReducer.next(phase: .recording, motion: stable, inference: result) == .recording
    )
}

@Test func quietE4InfersUniqueFromStableRecording() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e2")!, occupied: false)
    after.set(ChessSquare.parse("e4")!, occupied: true)
    let stable = BoardMotion.stable(after)
    let decision = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: stable,
        occupancy: after,
        commitHamming: 2,
        ignored: nil
    )
    #expect(decision == .infer(after))
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    guard case .unique = result else {
        Issue.record("expected unique e4, got \(result)")
        return
    }
    #expect(result.san == "e4")
}

@Test func genuineSettleDisturbedWaitsAndMapsToDisturbedPhase() {
    var moved = Occupancy.standardStart()
    moved.set(ChessSquare.parse("e2")!, occupied: false)
    moved.set(ChessSquare.parse("e4")!, occupied: true)
    let motion = BoardMotion.disturbed(since: moved)
    let decision = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: motion,
        occupancy: moved,
        commitHamming: 2,
        ignored: nil
    )
    #expect(decision == .wait)
    #expect(
        SessionReducer.next(phase: .recording, motion: motion, inference: .none) == .disturbed
    )
}

@Test func disturbedStableInfersInsteadOfWaiting() {
    var occ = Occupancy.standardStart()
    occ.set(ChessSquare.parse("e2")!, occupied: false)
    let stable = BoardMotion.stable(occ)
    let decision = LiveSettleDecision.action(
        phase: .disturbed,
        settleMotion: stable,
        occupancy: occ,
        commitHamming: 1,
        ignored: nil
    )
    #expect(decision == .infer(occ))
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

@Test func seededSettleIsImmediatelyStableOnSameOccupancy() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock().now
    let start = Occupancy.standardStart()
    d.seed(occupancy: start, at: t0)
    #expect(d.ingest(start, at: t0) == .stable(start))
}

@Test func commitHammingZeroStaysRecordingWhenMotionForcedStable() {
    let occ = Occupancy.standardStart()
    let decision = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: .stable(occ),
        occupancy: occ,
        commitHamming: 0,
        ignored: nil
    )
    #expect(decision == .wait)
    #expect(
        SessionReducer.next(phase: .recording, motion: .stable(occ), inference: .none) == .recording
    )
}

@Test func ignoredOccupancyExpiresAfterTTL() {
    let start = Occupancy.standardStart()
    var drift = start
    drift.set(ChessSquare.parse("e5")!, occupied: true)
    let t0 = ContinuousClock().now
    let skipped = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: .stable(drift),
        occupancy: drift,
        commitHamming: 1,
        ignored: drift,
        ignoredAt: t0,
        now: t0.advanced(by: .seconds(1))
    )
    #expect(skipped == .skipIgnored)
    let retry = LiveSettleDecision.action(
        phase: .recording,
        settleMotion: .stable(drift),
        occupancy: drift,
        commitHamming: 1,
        ignored: drift,
        ignoredAt: t0,
        now: t0.advanced(by: .seconds(2))
    )
    #expect(retry == .infer(drift))
}
