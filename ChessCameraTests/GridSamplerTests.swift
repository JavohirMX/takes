import CoreGraphics
import Testing
@testable import ChessCamera

@Test func a1IsBottomLeftWhenWhiteAtBottom() {
    let r = GridSampler.rect(
        fileIndex: 0,
        rankFromImageTop: 7,
        imageSize: 512,
        inset: 0
    )
    #expect(r.midX == 32)
    #expect(r.midY == CGFloat(512 - 32))
}

@Test func orientationMapsImageRankToA1() {
    let sq = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 7,
        orientation: .whiteAtBottom
    )
    #expect(sq.algebraic == "a1")
}

@Test func whiteAtTopMapsImageTopRightToA1() {
    let sq = GridSampler.square(
        fileIndex: 7,
        rankFromImageTop: 0,
        orientation: .whiteAtTop
    )
    #expect(sq.algebraic == "a1")
}

@Test func whiteAtTopMapsImageTopLeftToH1() {
    let sq = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 0,
        orientation: .whiteAtTop
    )
    #expect(sq.algebraic == "h1")
}
