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

/// Board Studio landscape pane: wide view hosting a landscape buffer.
@Test func landscapeViewLetterboxesLandscapeBuffer() {
    let view = CGSize(width: 1600, height: 900)   // landscape pane
    let buffer = CGSize(width: 1280, height: 720) // rotated capture
    let video = VideoMapping.aspectFitRect(contentSize: buffer, in: view)
    #expect(abs(video.width - 1600) < 0.5)
    #expect(abs(video.height - 900) < 0.5)
    #expect(abs(video.minX) < 0.5)
    #expect(abs(video.minY) < 0.5)

    let corner = CGPoint(x: 1279, y: 719)
    let viewPoint = VideoMapping.bufferToView(point: corner, viewSize: view, bufferSize: buffer)
    let back = VideoMapping.viewToBuffer(point: viewPoint, viewSize: view, bufferSize: buffer)
    #expect(back != nil)
    #expect(abs((back?.x ?? 0) - 1279) < 0.5)
    #expect(abs((back?.y ?? 0) - 719) < 0.5)
}

@Test func landscapeSidebarPanePillarboxWhenTallerBuffer() {
    // Camera column beside a 300pt sidebar can be portrait-tall while buffer is landscape.
    let view = CGSize(width: 700, height: 900)
    let buffer = CGSize(width: 1280, height: 720)
    let video = VideoMapping.aspectFitRect(contentSize: buffer, in: view)
    #expect(video.width <= view.width + 0.5)
    #expect(video.height <= view.height + 0.5)
    #expect(abs(video.midX - view.width / 2) < 0.5)
    #expect(abs(video.midY - view.height / 2) < 0.5)

    let center = CGPoint(x: video.midX, y: video.midY)
    let mapped = VideoMapping.viewToBuffer(point: center, viewSize: view, bufferSize: buffer)
    #expect(mapped != nil)
    #expect(abs((mapped?.x ?? 0) - 640) < 1)
    #expect(abs((mapped?.y ?? 0) - 360) < 1)
}
