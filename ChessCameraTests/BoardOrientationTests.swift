import Testing
@testable import Takes

@Test func previewRotationPutsWhiteAtBottom() {
    #expect(BoardOrientation.whiteAtBottom.previewRotationDegrees == 0)
    #expect(BoardOrientation.whiteAtRight.previewRotationDegrees == 90)
    #expect(BoardOrientation.whiteAtTop.previewRotationDegrees == 180)
    #expect(BoardOrientation.whiteAtLeft.previewRotationDegrees == 270)
}

@Test func fourCounterClockwiseRotationsReturnToStart() {
    var orientation = BoardOrientation.whiteAtBottom
    for _ in 0..<4 {
        orientation = orientation.rotatedCounterClockwise
    }
    #expect(orientation == .whiteAtBottom)
}

@Test func counterClockwiseCycleTurnsPreviewClockwise() {
    #expect(BoardOrientation.whiteAtBottom.rotatedCounterClockwise == .whiteAtRight)
    #expect(BoardOrientation.whiteAtRight.rotatedCounterClockwise == .whiteAtTop)
    #expect(BoardOrientation.whiteAtTop.rotatedCounterClockwise == .whiteAtLeft)
    #expect(BoardOrientation.whiteAtLeft.rotatedCounterClockwise == .whiteAtBottom)
}
