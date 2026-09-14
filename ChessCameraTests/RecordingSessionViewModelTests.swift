import ChessKit
import Testing
@testable import ChessCamera

@Test @MainActor
func twoCommitsUpdateLastSANAndPGN() throws {
    let model = RecordingSessionViewModel()
    model.startRecording()

    let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
    try model.commit(move: e4)
    #expect(model.lastSAN == "1. e4")
    #expect(model.committedSANs.count == 1)
    #expect(model.committedPlyCount == 1)

    let e5 = try #require(Move(san: "e5", position: model.engine.board.position))
    try model.commit(move: e5)
    #expect(model.lastSAN == "1... e5")
    #expect(model.committedSANs.count == 2)
    #expect(model.committedPlyCount == 2)
    #expect(model.engine.pgn.contains("e4"))
    #expect(model.engine.pgn.contains("e5"))
}

@Test @MainActor
func undoRestoresMirroredNotation() throws {
    let model = RecordingSessionViewModel()
    model.startRecording()
    let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
    try model.commit(move: e4)
    let e5 = try #require(Move(san: "e5", position: model.engine.board.position))
    try model.commit(move: e5)
    model.undoLast()
    #expect(model.lastSAN == "1. e4")
    #expect(model.committedSANs.count == 1)
}
