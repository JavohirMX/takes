import ChessKit
import Testing
@testable import Takes

@Test func infersE4FromStart() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e2")!, occupied: false)
    after.set(ChessSquare.parse("e4")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("e4", on: engine.board))
}

@Test func infersCaptureBxc6() throws {
    let engine = try GameEngine(fen: "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("b5")!, occupied: false)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("Bxc6", on: engine.board))
}

@Test func infersCastleShort() throws {
    let engine = try GameEngine(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e1")!, occupied: false)
    after.set(ChessSquare.parse("h1")!, occupied: false)
    after.set(ChessSquare.parse("g1")!, occupied: true)
    after.set(ChessSquare.parse("f1")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("O-O", on: engine.board))
}

@Test func infersCastleLong() throws {
    let engine = try GameEngine(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e1")!, occupied: false)
    after.set(ChessSquare.parse("a1")!, occupied: false)
    after.set(ChessSquare.parse("c1")!, occupied: true)
    after.set(ChessSquare.parse("d1")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("O-O-O", on: engine.board))
}

@Test func infersEnPassant() throws {
    let engine = try GameEngine(fen: "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e5")!, occupied: false)
    after.set(ChessSquare.parse("d5")!, occupied: false)
    after.set(ChessSquare.parse("d6")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("exd6", on: engine.board))
}

@Test func infersPromotionToQueen() throws {
    let engine = try GameEngine(fen: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e7")!, occupied: false)
    after.set(ChessSquare.parse("e8")!, occupied: true)
    let dest = ChessSquare.parse("e8")!
    let result = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [dest: .whiteQueen]
        ),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("e8=Q", on: engine.board))
}

@Test func infersNoneWhenOccupancyUnchanged() {
    let engine = GameEngine()
    let occ = engine.occupancy()
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: occ, current: occ, observedClasses: [:]),
        board: engine.board
    )
    #expect(result == .none)
}

@Test func infersIllegalWhenRandomBitsFlip() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("a1")!, occupied: false)
    after.set(ChessSquare.parse("c3")!, occupied: true)
    after.set(ChessSquare.parse("f5")!, occupied: true)
    after.set(ChessSquare.parse("h8")!, occupied: false)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result == .illegal)
}

@Test func infersE4WhenNeighborFileIsAlsoFilled() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e2")!, occupied: false)
    after.set(ChessSquare.parse("e4")!, occupied: true)
    after.set(ChessSquare.parse("f4")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("e4", on: engine.board))
}

@Test func doesNotInferE4WhenOriginStillOccupiedAmongGhostFills() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e4")!, occupied: true)
    after.set(ChessSquare.parse("f4")!, occupied: true)
    let e4 = ChessSquare.parse("e4")!
    #expect(before.hammingDistance(to: after) == 2)
    let result = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [e4: .whitePawn]
        ),
        board: engine.board
    )
    // Quiet Hamming-2 requires an exact occupancy match; origin still filled → illegal.
    #expect(result == .illegal)
}

@Test func infersE4WhenOneGhostSquareIsOccupied() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e2")!, occupied: false)
    after.set(ChessSquare.parse("e4")!, occupied: true)
    after.set(ChessSquare.parse("a3")!, occupied: true)
    #expect(after.hammingDistance(to: before) == 3)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("e4", on: engine.board))
}

@Test func infersE5WhenOneGhostSquareIsOccupied() throws {
    let engine = GameEngine()
    try engine.apply(san: "e4")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e7")!, occupied: false)
    after.set(ChessSquare.parse("e5")!, occupied: true)
    after.set(ChessSquare.parse("h6")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == canonicalSAN("e5", on: engine.board))
}

@Test func infersIllegalWhenHammingIsSix() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("a1")!, occupied: false)
    after.set(ChessSquare.parse("b1")!, occupied: false)
    after.set(ChessSquare.parse("c3")!, occupied: true)
    after.set(ChessSquare.parse("f5")!, occupied: true)
    after.set(ChessSquare.parse("g6")!, occupied: true)
    after.set(ChessSquare.parse("h8")!, occupied: false)
    #expect(after.hammingDistance(to: before) == 6)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result == .illegal)
}

@Test func capturePlusGhostRimSquareIsIllegalWithExactQuietSlack() throws {
    let engine = try GameEngine(fen: "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("b5")!, occupied: false)
    after.set(ChessSquare.parse("h8")!, occupied: false)
    #expect(before.hammingDistance(to: after) == 2)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result == .illegal)
}

@Test func checkCaptureBxc6IsUnique() throws {
    let engine = try GameEngine(fen: "4k3/8/2n5/1B6/8/8/8/4K3 w - - 0 1")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("b5")!, occupied: false)
    #expect(before.hammingDistance(to: after) == 1)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    let expected = canonicalSAN("Bxc6+", on: engine.board) ?? canonicalSAN("Bxc6", on: engine.board)
    #expect(result.san == expected)
}

@Test func twoCapturesFromSameOriginStayAmbiguous() throws {
    let engine = try GameEngine(fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQkq - 2 3")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("h5")!, occupied: false)
    #expect(before.hammingDistance(to: after) == 1)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    guard case .ambiguous(let moves) = result else {
        Issue.record("expected ambiguous queen captures, got \(result)")
        return
    }
    #expect(moves.count >= 2)
    #expect(MoveInferrer.debugSans(for: result).hasPrefix("amb "))
}

@Test func twoCapturesResolvedToQxf7ByPieceColor() throws {
    let engine = try GameEngine(fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQkq - 2 3")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("h5")!, occupied: false)
    #expect(before.hammingDistance(to: after) == 1)
    let f7 = ChessSquare.parse("f7")!
    let e5 = ChessSquare.parse("e5")!
    let result = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [
                f7: .whiteQueen,
                e5: .blackPawn
            ]
        ),
        board: engine.board
    )
    let expected = canonicalSAN("Qxf7+", on: engine.board) ?? canonicalSAN("Qxf7", on: engine.board)
    #expect(result.san == expected)
}

@Test func twoCapturesResolvedToQxe5ByPieceColor() throws {
    let engine = try GameEngine(fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQkq - 2 3")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("h5")!, occupied: false)
    #expect(before.hammingDistance(to: after) == 1)
    let f7 = ChessSquare.parse("f7")!
    let e5 = ChessSquare.parse("e5")!
    let result = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [
                f7: .blackPawn,
                e5: .whiteQueen
            ]
        ),
        board: engine.board
    )
    let expected = canonicalSAN("Qxe5+", on: engine.board) ?? canonicalSAN("Qxe5", on: engine.board)
    #expect(result.san == expected)
}

@Test func twoCapturesResolvedWhenOnlyCapturedSquareColorObserved() throws {
    let engine = try GameEngine(fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQkq - 2 3")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("h5")!, occupied: false)
    #expect(before.hammingDistance(to: after) == 1)
    let f7 = ChessSquare.parse("f7")!
    let result = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [f7: .whiteQueen]
        ),
        board: engine.board
    )
    let expected = canonicalSAN("Qxf7+", on: engine.board) ?? canonicalSAN("Qxf7", on: engine.board)
    #expect(result.san == expected)
}

@Test func infersE4AndE5AsTwoPlyFromStart() throws {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e2")!, occupied: false)
    after.set(ChessSquare.parse("e4")!, occupied: true)
    after.set(ChessSquare.parse("e7")!, occupied: false)
    after.set(ChessSquare.parse("e5")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    guard case .unique(let moves) = result else {
        Issue.record("expected unique e4 then e5, got \(result)")
        return
    }
    #expect(moves.count == 2)
    guard moves.count == 2 else { return }
    #expect(moves[0].san == canonicalSAN("e4", on: engine.board))
    let mid = GameEngine()
    try mid.apply(san: "e4")
    #expect(moves[1].san == canonicalSAN("e5", on: mid.board))
}

@Test func infersIllegalWhenMaxPliesIsOneButDeltaNeedsTwo() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e2")!, occupied: false)
    after.set(ChessSquare.parse("e4")!, occupied: true)
    after.set(ChessSquare.parse("e7")!, occupied: false)
    after.set(ChessSquare.parse("e5")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board,
        maxPlies: 1
    )
    #expect(result == .illegal)
}

@Test func infersOnlyE5WhenE4AlreadyCommitted() throws {
    let engine = GameEngine()
    try engine.apply(san: "e4")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e7")!, occupied: false)
    after.set(ChessSquare.parse("e5")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    guard case .unique(let moves) = result else {
        Issue.record("expected unique e5, got \(result)")
        return
    }
    #expect(moves.count == 1)
    #expect(moves[0].san == canonicalSAN("e5", on: engine.board))
}

@Test func castlePlusOpponentQuietNeedsSequentialCommitsNotTwoPly() throws {
    let engine = try GameEngine(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e1")!, occupied: false)
    after.set(ChessSquare.parse("h1")!, occupied: false)
    after.set(ChessSquare.parse("g1")!, occupied: true)
    after.set(ChessSquare.parse("f1")!, occupied: true)
    after.set(ChessSquare.parse("e8")!, occupied: false)
    after.set(ChessSquare.parse("e7")!, occupied: true)
    #expect(before.hammingDistance(to: after) == 6)
    #expect(!MoveInferrer.allowsTwoPly(visualHamming: 6))
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result == .illegal)
}

@Test func queenMoveSucceedsEvenWhenDestinationLabeledPawn() throws {
    let engine = try GameEngine(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("d1")!, occupied: false)
    after.set(ChessSquare.parse("f3")!, occupied: true)
    #expect(before.hammingDistance(to: after) == 2)
    let withPawnLabel = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [ChessSquare.parse("f3")!: .whitePawn]
        ),
        board: engine.board
    )
    #expect(withPawnLabel.san == canonicalSAN("Qf3", on: engine.board))

    let unlabeled = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(unlabeled.san == canonicalSAN("Qf3", on: engine.board))
}

@Test func bishopMoveSucceedsEvenWhenDestinationLabeledPawn() throws {
    let engine = try GameEngine(fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("f1")!, occupied: false)
    after.set(ChessSquare.parse("c4")!, occupied: true)
    #expect(before.hammingDistance(to: after) == 2)
    let withPawnLabel = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [ChessSquare.parse("c4")!: .whitePawn]
        ),
        board: engine.board
    )
    #expect(withPawnLabel.san == canonicalSAN("Bc4", on: engine.board))
}

@Test func quietMoveSlackIsExact() {
    #expect(MoveInferrer.slack(for: 2) == 0)
    #expect(MoveInferrer.slack(for: 1) == 1)
    #expect(MoveInferrer.slack(for: 3) == 1)
    #expect(MoveInferrer.slack(for: 4) == 1)
    #expect(MoveInferrer.slack(for: 6) == 0)
    #expect(MoveInferrer.allowsTwoPly(visualHamming: 4))
    #expect(!MoveInferrer.allowsTwoPly(visualHamming: 2))
}

@Test func infersNf3WhenG1OriginIsVacatedEvenIfBinaryOccupancyLagged() throws {
    let engine = try GameEngine(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
    let before = engine.occupancy()
    var after = before
    // Simulate camera lagging on clearing g1: only f3 is marked filled
    after.set(ChessSquare.parse("f3")!, occupied: true)
    #expect(before.hammingDistance(to: after) == 1)

    // Unlabeled / empty observedClasses cannot tell if f2, d1, or g1 moved -> stays ambiguous
    let unlabeled = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    guard case .ambiguous(let ambiguousMoves) = unlabeled else {
        Issue.record("expected ambiguous moves when observedClasses is empty, got \(unlabeled)")
        return
    }
    #expect(ambiguousMoves.count == 3)

    // With observedClasses showing f2 and d1 occupied, but g1 empty -> resolves uniquely to Nf3
    let withClasses = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [
                ChessSquare.parse("f3")!: .whiteKnight,
                ChessSquare.parse("f2")!: .whitePawn,
                ChessSquare.parse("d1")!: .whiteQueen,
                ChessSquare.parse("g1")!: .empty
            ]
        ),
        board: engine.board
    )
    #expect(withClasses.san == canonicalSAN("Nf3", on: engine.board))

    // Also works when g1 has no entry in observedClasses at all (unobserved / no detection)
    let withAbsentG1 = MoveInferrer.infer(
        delta: VisualDelta(
            previous: before,
            current: after,
            observedClasses: [
                ChessSquare.parse("f3")!: .whiteKnight,
                ChessSquare.parse("f2")!: .whitePawn,
                ChessSquare.parse("d1")!: .whiteQueen
            ]
        ),
        board: engine.board
    )
    #expect(withAbsentG1.san == canonicalSAN("Nf3", on: engine.board))
}

private func canonicalSAN(_ san: String, on board: Board) -> String? {
    Move(san: san, position: board.position)?.san
}

