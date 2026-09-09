import ChessKit
import Testing
@testable import ChessCamera

@Test func recordingBecomesDisturbedOnOccupancyChange() {
    let next = SessionReducer.next(
        phase: .recording,
        motion: .disturbed(since: Occupancy()),
        inference: .none
    )
    #expect(next == .disturbed)
}

@Test func disturbedUniqueReturnsRecording() {
    let move = Move(san: "e4", position: Board().position)!
    let next = SessionReducer.next(
        phase: .disturbed,
        motion: .stable(Occupancy.standardStart()),
        inference: .unique(move)
    )
    #expect(next == .recording)
}

@Test func disturbedNoneReturnsRecording() {
    let next = SessionReducer.next(
        phase: .disturbed,
        motion: .stable(Occupancy.standardStart()),
        inference: .none
    )
    #expect(next == .recording)
}

@Test func disturbedIllegalReturnsAwaitingEdit() {
    let next = SessionReducer.next(
        phase: .disturbed,
        motion: .stable(Occupancy()),
        inference: .illegal
    )
    #expect(next == .awaitingEdit)
}

@Test func disturbedAmbiguousReturnsAwaitingEdit() {
    let move = Move(san: "e4", position: Board().position)!
    let next = SessionReducer.next(
        phase: .disturbed,
        motion: .stable(Occupancy()),
        inference: .ambiguous([move])
    )
    #expect(next == .awaitingEdit)
}
