import Testing
@testable import ChessCamera

@Test func remapClockwiseSendsA1ToH1() {
    let a1 = ChessSquare.parse("a1")!
    let classes: [ChessSquare: PieceClass] = [a1: .whiteRook]
    let remapped = FenCodec.remapped(classes, from: .whiteAtBottom, to: .whiteAtLeft)
    #expect(remapped[ChessSquare.parse("h1")!] == .whiteRook)
    #expect(remapped[a1] == nil)
}

@Test func remap180SendsA1ToH8() {
    let a1 = ChessSquare.parse("a1")!
    let classes: [ChessSquare: PieceClass] = [a1: .whiteRook]
    let remapped = FenCodec.remapped(classes, from: .whiteAtBottom, to: .whiteAtTop)
    #expect(remapped[ChessSquare.parse("h8")!] == .whiteRook)
}

@Test func fourClockwiseRemapsReturnToStart() {
    var classes = FenCodec.standardClasses()
    var orientation = BoardOrientation.whiteAtBottom
    for _ in 0..<4 {
        let next = orientation.rotatedClockwise
        classes = FenCodec.remapped(classes, from: orientation, to: next)
        orientation = next
    }
    #expect(orientation == .whiteAtBottom)
    #expect(FenCodec.isStandardStart(FenCodec.fen(from: classes)))
}

@Test func inferOrientationFromWhiteKingUnderWhiteAtBottom() {
    func classes(kingAt algebraic: String) -> [ChessSquare: PieceClass] {
        [ChessSquare.parse(algebraic)!: .whiteKing]
    }
    #expect(FenCodec.inferOrientation(from: classes(kingAt: "e1")) == .whiteAtBottom)
    #expect(FenCodec.inferOrientation(from: classes(kingAt: "d8")) == .whiteAtTop)
    #expect(FenCodec.inferOrientation(from: classes(kingAt: "a4")) == .whiteAtLeft)
    #expect(FenCodec.inferOrientation(from: classes(kingAt: "h5")) == .whiteAtRight)
}

@Test func inferOrientationDefaultsToWhiteAtBottomWithoutKing() {
    #expect(FenCodec.inferOrientation(from: [:]) == .whiteAtBottom)
}
