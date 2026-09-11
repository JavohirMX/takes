import CoreGraphics
import Foundation
import Testing
@testable import ChessCamera

@Test func interpolatedCorners() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 80, y: 0),
        bottomRight: CGPoint(x: 80, y: 80),
        bottomLeft: CGPoint(x: 0, y: 80)
    )
    #expect(quad.interpolated(u: 0, v: 0) == CGPoint(x: 0, y: 0))
    #expect(quad.interpolated(u: 1, v: 1) == CGPoint(x: 80, y: 80))
    let mid = quad.interpolated(u: 0.5, v: 0.5)
    #expect(abs(mid.x - 40) < 0.01)
    #expect(abs(mid.y - 40) < 0.01)
}

@Test func inverseUvRoundTripsAxisAlignedQuad() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 80, y: 0),
        bottomRight: CGPoint(x: 80, y: 80),
        bottomLeft: CGPoint(x: 0, y: 80)
    )
    let point = quad.interpolated(u: 0.25, v: 0.75)
    let uv = quad.uv(containing: point)
    #expect(uv != nil)
    #expect(abs((uv?.x ?? -1) - 0.25) < 0.001)
    #expect(abs((uv?.y ?? -1) - 0.75) < 0.001)
    #expect(quad.uv(containing: CGPoint(x: -10, y: 40)) == nil)
}

@Test func inverseUvRoundTripsSkewedQuad() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 10, y: 20),
        topRight: CGPoint(x: 90, y: 10),
        bottomRight: CGPoint(x: 100, y: 80),
        bottomLeft: CGPoint(x: 5, y: 90)
    )
    let point = quad.interpolated(u: 0.3, v: 0.7)
    let uv = quad.uv(containing: point)
    #expect(uv != nil)
    #expect(abs((uv?.x ?? -1) - 0.3) < 0.01)
    #expect(abs((uv?.y ?? -1) - 0.7) < 0.01)
}

@Test func correlationIsOneForIdenticalPatches() {
    let patch = [UInt8](0..<49)
    #expect(abs(NormalizedCorrelation.score(patch, patch) - 1) < 0.0001)
}

@Test func trackerFollowsShiftedCornerMark() throws {
    let mark = try makeMarkImage(size: 80, markAt: CGPoint(x: 20, y: 24))
    let shifted = try makeMarkImage(size: 80, markAt: CGPoint(x: 28, y: 30))
    guard let start = GrayFrame.from(cgImage: mark),
          let next = GrayFrame.from(cgImage: shifted) else {
        Issue.record("gray conversion failed")
        return
    }
    var tracker = CornerTracker(patchSize: 15, searchRadius: 16, minimumScore: 0.4)
    let origin = CGPoint(x: 20, y: 24)
    let quad = Quadrilateral(
        topLeft: origin,
        topRight: CGPoint(x: 70, y: 10),
        bottomRight: CGPoint(x: 70, y: 70),
        bottomLeft: CGPoint(x: 10, y: 70)
    )
    tracker.capture(from: start, quad: quad)
    let result = tracker.track(in: next, from: quad)
    #expect(abs(result.quad.topLeft.x - 28) <= 2)
    #expect(abs(result.quad.topLeft.y - 30) <= 2)
    #expect(result.confidences[0] > 0.5)
}

private func makeMarkImage(size: Int, markAt: CGPoint) throws -> CGImage {
    var bytes = [UInt8](repeating: 30, count: size * size * 4)
    let mx = Int(markAt.x)
    let my = Int(markAt.y)
    for dy in -4...4 {
        for dx in -4...4 {
            let x = mx + dx
            let y = my + dy
            guard x >= 0, y >= 0, x < size, y < size else { continue }
            let i = (y * size + x) * 4
            bytes[i] = 240
            bytes[i + 1] = 240
            bytes[i + 2] = 240
            bytes[i + 3] = 255
        }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        struct ImageError: Error {}
        throw ImageError()
    }
    return image
}
