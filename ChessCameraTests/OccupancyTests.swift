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

@Test func occupancyPriorDropsCenterFillThatNoLegalMoveCanMake() {
    let engine = GameEngine()
    let prior = GameEngine.occupancyPrior(of: engine.board, includeReplies: false)
    let start = engine.occupancy()
    var noisy = start
    noisy.set(ChessSquare.parse("e5")!, occupied: true)
    #expect(prior.apply(detected: noisy, previous: start) == start)
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

@Test func occupancyPriorDropsGhostFillsWithoutClears() {
    let engine = GameEngine()
    let prior = GameEngine.occupancyPrior(of: engine.board)
    let start = engine.occupancy()
    var ghosts = start
    ghosts.set(ChessSquare.parse("e4")!, occupied: true)
    ghosts.set(ChessSquare.parse("f4")!, occupied: true)
    #expect(prior.apply(detected: ghosts, previous: start) == start)
}

@Test func occupancyPriorDropsFillsWhenTooManyPawnClears() {
    let engine = GameEngine()
    let prior = GameEngine.occupancyPrior(of: engine.board)
    let start = engine.occupancy()
    var noisy = start
    noisy.set(ChessSquare.parse("e4")!, occupied: true)
    for name in ["a2", "b2", "c2", "d2", "e2"] {
        noisy.set(ChessSquare.parse(name)!, occupied: false)
    }
    let gated = prior.apply(detected: noisy, previous: start)
    #expect(gated == start)
    #expect(!gated.occupied(ChessSquare.parse("e4")!))
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

@Test func occupancyFusionTrustsFlaggedFingerprintWhenYOLOMissesPawn() {
    let start = Occupancy.standardStart()
    var fingerprint = start
    fingerprint.set(ChessSquare.parse("e2")!, occupied: false)
    fingerprint.set(ChessSquare.parse("e4")!, occupied: true)
    var changed = Occupancy()
    changed.set(ChessSquare.parse("e2")!, occupied: true)
    changed.set(ChessSquare.parse("e4")!, occupied: true)
    let fused = OccupancyFusion.combine(
        previous: start,
        yolo: start,
        fingerprint: fingerprint,
        changed: changed
    )
    #expect(fused.hammingDistance(to: start) == 2)
    #expect(!fused.occupied(ChessSquare.parse("e2")!))
    #expect(fused.occupied(ChessSquare.parse("e4")!))
}

@Test func occupancyFusionAppliesUnflaggedYOLOGhostFill() {
    // Fusion trusts silent-FP YOLO; OccupancyPrior drops fills with no clears live.
    let start = Occupancy.standardStart()
    var yolo = start
    yolo.set(ChessSquare.parse("f4")!, occupied: true)
    let fused = OccupancyFusion.combine(
        previous: start,
        yolo: yolo,
        fingerprint: start,
        changed: Occupancy()
    )
    #expect(fused.occupied(ChessSquare.parse("f4")!))
    #expect(fused.hammingDistance(to: start) == 1)
}

@Test func occupancyFusionAppliesYOLOMoveWhenFingerprintIsSilent() {
    let start = Occupancy.standardStart()
    var yolo = start
    yolo.set(ChessSquare.parse("e2")!, occupied: false)
    yolo.set(ChessSquare.parse("e4")!, occupied: true)
    let fused = OccupancyFusion.combine(
        previous: start,
        yolo: yolo,
        fingerprint: start,
        changed: Occupancy()
    )
    #expect(fused.hammingDistance(to: start) == 2)
    #expect(!fused.occupied(ChessSquare.parse("e2")!))
    #expect(fused.occupied(ChessSquare.parse("e4")!))
}

@Test func occupancyFusionKeepsOriginWhenFingerprintFailsEmptied() {
    let start = Occupancy.standardStart()
    var yolo = start
    yolo.set(ChessSquare.parse("e2")!, occupied: false)
    yolo.set(ChessSquare.parse("e4")!, occupied: true)
    var fingerprint = start
    fingerprint.set(ChessSquare.parse("e4")!, occupied: true)
    var changed = Occupancy()
    changed.set(ChessSquare.parse("e2")!, occupied: true)
    changed.set(ChessSquare.parse("e4")!, occupied: true)
    let fused = OccupancyFusion.combine(
        previous: start,
        yolo: yolo,
        fingerprint: fingerprint,
        changed: changed
    )
    // Disagreement on e2 with YOLO≠previous → keep committed origin.
    #expect(fused.occupied(ChessSquare.parse("e2")!))
    #expect(fused.occupied(ChessSquare.parse("e4")!))
}

@Test func occupancyFusionAppliesFlaggedAgreementMove() {
    let start = Occupancy.standardStart()
    var yolo = start
    yolo.set(ChessSquare.parse("e2")!, occupied: false)
    yolo.set(ChessSquare.parse("e4")!, occupied: true)
    var fingerprint = yolo
    var changed = Occupancy()
    changed.set(ChessSquare.parse("e2")!, occupied: true)
    changed.set(ChessSquare.parse("e4")!, occupied: true)
    let fused = OccupancyFusion.combine(
        previous: start,
        yolo: yolo,
        fingerprint: fingerprint,
        changed: changed
    )
    #expect(fused.hammingDistance(to: start) == 2)
    #expect(!fused.occupied(ChessSquare.parse("e2")!))
    #expect(fused.occupied(ChessSquare.parse("e4")!))

    let engine = GameEngine()
    let gated = GameEngine.occupancyPrior(of: engine.board).apply(detected: fused, previous: start)
    var smoother = OccupancySmoother()
    smoother.reset(seeding: start)
    var smoothed = Occupancy()
    for _ in 0..<3 {
        smoothed = smoother.ingest(gated)
    }
    #expect(smoothed.hammingDistance(to: start) == 2)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: start, current: smoothed, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == "e4")
}

@Test func occupancyNoiseGateFreezesOnlyOnHighFusedHamming() {
    #expect(!OccupancyNoiseGate.shouldFreeze(fusedHamming: 2))
    #expect(!OccupancyNoiseGate.shouldFreeze(fusedHamming: 4))
    #expect(OccupancyNoiseGate.shouldFreeze(fusedHamming: 5))
    #expect(!OccupancyNoiseGate.fingerprintUnusable(changedCount: 5))
    #expect(OccupancyNoiseGate.fingerprintUnusable(changedCount: 6))
    #expect(OccupancyNoiseGate.fingerprintUnusable(changedCount: 15))
}

@Test func occupancyChaosIgnoresFingerprintAndUsesYOLO() {
    let start = Occupancy.standardStart()
    var yolo = start
    yolo.set(ChessSquare.parse("e2")!, occupied: false)
    yolo.set(ChessSquare.parse("e4")!, occupied: true)
    // Photometric chaos would rewrite many squares; pipeline skips FP and uses YOLO.
    #expect(OccupancyNoiseGate.fingerprintUnusable(changedCount: 15))
    #expect(!OccupancyNoiseGate.shouldFreeze(fusedHamming: start.hammingDistance(to: yolo)))
    let fused = yolo
    #expect(fused.hammingDistance(to: start) == 2)
}

@Test func recordedSessionMissedPawnFusesToUniqueE4() {
    let start = Occupancy.standardStart()
    var fingerprint = start
    fingerprint.set(ChessSquare.parse("e2")!, occupied: false)
    fingerprint.set(ChessSquare.parse("e4")!, occupied: true)
    var changed = Occupancy()
    changed.set(ChessSquare.parse("e2")!, occupied: true)
    changed.set(ChessSquare.parse("e4")!, occupied: true)
    let fused = OccupancyFusion.combine(
        previous: start,
        yolo: start,
        fingerprint: fingerprint,
        changed: changed
    )
    let engine = GameEngine()
    let gated = GameEngine.occupancyPrior(of: engine.board).apply(detected: fused, previous: start)
    var smoother = OccupancySmoother()
    smoother.reset(seeding: start)
    var smoothed = Occupancy()
    for _ in 0..<3 {
        smoothed = smoother.ingest(gated)
    }
    #expect(smoothed.hammingDistance(to: start) == 2)
    #expect(
        LiveSettleDecision.action(
            phase: .recording,
            settleMotion: .stable(smoothed),
            occupancy: smoothed,
            commitHamming: 2,
            ignored: nil
        ) == .infer(smoothed)
    )
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: start, current: smoothed, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == "e4")
}

@Test func recordedSessionGhostFillsStayStart() {
    let engine = GameEngine()
    let start = engine.occupancy()
    var yolo = start
    yolo.set(ChessSquare.parse("e4")!, occupied: true)
    yolo.set(ChessSquare.parse("f4")!, occupied: true)
    let gated = GameEngine.occupancyPrior(of: engine.board).apply(detected: yolo, previous: start)
    #expect(gated == start)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: start, current: gated, observedClasses: [:]),
        board: engine.board
    )
    #expect(result == .none)
}

@Test func differingSquaresReturnsChangedSquaresInBitIndexOrder() {
    let start = Occupancy.standardStart()
    #expect(start.differingSquares(with: start).isEmpty)

    var modified = start
    modified.set(ChessSquare.parse("e2")!, occupied: false)
    modified.set(ChessSquare.parse("e4")!, occupied: true)

    let diff = start.differingSquares(with: modified)
    #expect(diff == [ChessSquare.parse("e2")!, ChessSquare.parse("e4")!])
    #expect(diff.map(\.algebraic) == ["e2", "e4"])
}

@Test func differingSquaresIllegalDeltaSquares() {
    let start = Occupancy.standardStart()
    var modified = start
    modified.set(ChessSquare.parse("e4")!, occupied: true)
    modified.set(ChessSquare.parse("d5")!, occupied: true)

    let diff = start.differingSquares(with: modified)
    #expect(diff == [ChessSquare.parse("e4")!, ChessSquare.parse("d5")!])
    #expect(diff.map(\.algebraic) == ["e4", "d5"])
}
