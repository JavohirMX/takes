import ChessKit
import Testing
@testable import ChessCamera

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

private func canonicalSAN(_ san: String, on board: Board) -> String? {
    Move(san: san, position: board.position)?.san
}
