import CoreGraphics
import Testing
@testable import ChessCamera

@Test func viewToBufferMapsVideoCenterOfLetterboxed16By9() {
    let view = CGSize(width: 900, height: 1600)   // 9:16
    let buffer = CGSize(width: 1600, height: 900) // 16:9
    let video = VideoMapping.aspectFitRect(contentSize: buffer, in: view)
    let center = CGPoint(x: video.midX, y: video.midY)
    let mapped = VideoMapping.viewToBuffer(point: center, viewSize: view, bufferSize: buffer)
    #expect(mapped != nil)
    #expect(abs((mapped?.x ?? 0) - 800) < 0.5)
    #expect(abs((mapped?.y ?? 0) - 450) < 0.5)
}

@Test func viewToBufferReturnsNilOutsideLetterbox() {
    let view = CGSize(width: 900, height: 1600)
    let buffer = CGSize(width: 1600, height: 900)
    let mapped = VideoMapping.viewToBuffer(
        point: CGPoint(x: 450, y: 10),
        viewSize: view,
        bufferSize: buffer
    )
    #expect(mapped == nil)
}

@Test func bufferToViewRoundTripsCorner() {
    let view = CGSize(width: 900, height: 1600)
    let buffer = CGSize(width: 1600, height: 900)
    let origin = CGPoint(x: 0, y: 0)
    let viewPoint = VideoMapping.bufferToView(point: origin, viewSize: view, bufferSize: buffer)
    let back = VideoMapping.viewToBuffer(point: viewPoint, viewSize: view, bufferSize: buffer)
    #expect(back != nil)
    #expect(abs((back?.x ?? 1) - 0) < 0.5)
    #expect(abs((back?.y ?? 1) - 0) < 0.5)
}
