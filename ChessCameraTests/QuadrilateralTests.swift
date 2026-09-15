import CoreGraphics
import Foundation
import Testing
@testable import ChessCamera

@Test func expandedQuadMovesCornersOutward() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 100, y: 100),
        topRight: CGPoint(x: 300, y: 100),
        bottomRight: CGPoint(x: 300, y: 300),
        bottomLeft: CGPoint(x: 100, y: 300)
    )
    let padded = quad.expanded(by: 0.15)
    #expect(abs(padded.topLeft.x - 70) < 0.01)
    #expect(abs(padded.topLeft.y - 70) < 0.01)
    #expect(abs(padded.topRight.x - 330) < 0.01)
    #expect(abs(padded.topRight.y - 70) < 0.01)
    #expect(abs(padded.bottomRight.x - 330) < 0.01)
    #expect(abs(padded.bottomRight.y - 330) < 0.01)
    #expect(abs(padded.bottomLeft.x - 70) < 0.01)
    #expect(abs(padded.bottomLeft.y - 330) < 0.01)
}

@Test func expandedThenClampedStaysInBounds() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 10, y: 10),
        topRight: CGPoint(x: 90, y: 8),
        bottomRight: CGPoint(x: 95, y: 92),
        bottomLeft: CGPoint(x: 12, y: 88)
    )
    let size = CGSize(width: 100, height: 100)
    let clamped = quad.expanded(by: 0.5).clamped(to: size)
    for point in clamped.points {
        #expect(point.x >= 0)
        #expect(point.x <= size.width)
        #expect(point.y >= 0)
        #expect(point.y <= size.height)
    }
}

@Test func expandedIfFitsDoesNotShearClippedBoards() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 4, y: 4),
        topRight: CGPoint(x: 90, y: 6),
        bottomRight: CGPoint(x: 92, y: 96),
        bottomLeft: CGPoint(x: 6, y: 94)
    )
    let size = CGSize(width: 100, height: 100)
    let fitted = quad.expandedIfFits(by: 0.15, in: size)
    for point in fitted.points {
        #expect(point.x >= 0)
        #expect(point.x <= size.width)
        #expect(point.y >= 0)
        #expect(point.y <= size.height)
    }
    let sheared = quad.expanded(by: 0.15).clamped(to: size)
    #expect(fitted != sheared)
}

@Test func expandedIfFitsKeepsPaddingWhenBoardIsInset() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 40, y: 40),
        topRight: CGPoint(x: 160, y: 40),
        bottomRight: CGPoint(x: 160, y: 160),
        bottomLeft: CGPoint(x: 40, y: 160)
    )
    let fitted = quad.expandedIfFits(by: 0.15, in: CGSize(width: 200, height: 200))
    #expect(fitted == quad.expanded(by: 0.15))
}

@Test func paddedLatticeRoundTripsOriginalQuad() {
    let original = Quadrilateral(
        topLeft: CGPoint(x: 200, y: 100),
        topRight: CGPoint(x: 800, y: 120),
        bottomRight: CGPoint(x: 780, y: 700),
        bottomLeft: CGPoint(x: 180, y: 680)
    )
    let fraction: CGFloat = 0.15
    let padded = original.expanded(by: fraction)
    let imageSize: CGFloat = 512
    let u0 = fraction / (1 + 2 * fraction)
    let u1 = (1 + fraction) / (1 + 2 * fraction)
    var points: [CGPoint] = []
    points.reserveCapacity(RefinedBoardGrid.pointCount)
    for row in 0...8 {
        for col in 0...8 {
            let u = u0 + (u1 - u0) * CGFloat(col) / 8
            let v = u0 + (u1 - u0) * CGFloat(row) / 8
            points.append(CGPoint(x: u * imageSize, y: v * imageSize))
        }
    }
    let grid = RefinedBoardGrid(imageSize: imageSize, points: points)
    let snapped = grid.cameraQuad(mappingWith: padded)
    // cameraQuad uses perspective mapping (matches BoardWarper), not bilinear expand UV.
    let expected = Quadrilateral(
        topLeft: padded.perspectiveMapped(u: u0, v: u0),
        topRight: padded.perspectiveMapped(u: u1, v: u0),
        bottomRight: padded.perspectiveMapped(u: u1, v: u1),
        bottomLeft: padded.perspectiveMapped(u: u0, v: u1)
    )
    #expect(abs(snapped.topLeft.x - expected.topLeft.x) < 1)
    #expect(abs(snapped.topLeft.y - expected.topLeft.y) < 1)
    #expect(abs(snapped.topRight.x - expected.topRight.x) < 1)
    #expect(abs(snapped.topRight.y - expected.topRight.y) < 1)
    #expect(abs(snapped.bottomRight.x - expected.bottomRight.x) < 1)
    #expect(abs(snapped.bottomRight.y - expected.bottomRight.y) < 1)
    #expect(abs(snapped.bottomLeft.x - expected.bottomLeft.x) < 1)
    #expect(abs(snapped.bottomLeft.y - expected.bottomLeft.y) < 1)

    // Bilinear expand still places the original at (u0,u0) in interpolated UV.
    let uv = padded.uv(containing: original.topLeft, epsilon: 0.02)
    #expect(uv != nil)
    #expect(abs((uv?.x ?? -1) - u0) < 0.02)
    #expect(abs((uv?.y ?? -1) - u0) < 0.02)
}

@Test func perspectiveDiffersFromBilinearOnTrapezoid() {
    // Strong foreshortening: top edge much shorter than bottom.
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 300, y: 80),
        topRight: CGPoint(x: 500, y: 80),
        bottomRight: CGPoint(x: 900, y: 700),
        bottomLeft: CGPoint(x: 100, y: 700)
    )
    let midTopPerspective = quad.perspectiveMapped(u: 0.5, v: 0)
    let midTopBilinear = quad.interpolated(u: 0.5, v: 0)
    let midLeftPerspective = quad.perspectiveMapped(u: 0, v: 0.5)
    let midLeftBilinear = quad.interpolated(u: 0, v: 0.5)

    // Midpoints of the short top edge coincide (collinear), but the left edge midpoints diverge.
    #expect(abs(midTopPerspective.x - midTopBilinear.x) < 0.5)
    #expect(abs(midTopPerspective.y - midTopBilinear.y) < 0.5)
    let leftDelta = hypot(
        midLeftPerspective.x - midLeftBilinear.x,
        midLeftPerspective.y - midLeftBilinear.y
    )
    #expect(leftDelta > 5)

    // Corners still match exactly.
    #expect(quad.perspectiveMapped(u: 0, v: 0) == quad.topLeft)
    #expect(quad.perspectiveMapped(u: 1, v: 0) == quad.topRight)
    #expect(quad.perspectiveMapped(u: 1, v: 1) == quad.bottomRight)
    #expect(quad.perspectiveMapped(u: 0, v: 1) == quad.bottomLeft)
}

@Test func perspectiveUVRoundTripsMappedPoints() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 220, y: 90),
        topRight: CGPoint(x: 780, y: 110),
        bottomRight: CGPoint(x: 860, y: 720),
        bottomLeft: CGPoint(x: 140, y: 690)
    )
    let samples: [(CGFloat, CGFloat)] = [
        (0, 0), (1, 0), (1, 1), (0, 1),
        (0.5, 0), (0, 0.5), (0.5, 0.5), (0.25, 0.75), (0.8, 0.2)
    ]
    for (u, v) in samples {
        let mapped = quad.perspectiveMapped(u: u, v: v)
        let back = quad.perspectiveUV(containing: mapped, epsilon: 0.02)
        #expect(back != nil)
        #expect(abs((back?.x ?? -1) - u) < 0.01)
        #expect(abs((back?.y ?? -1) - v) < 0.01)
    }
}

@Test func perspectiveMatchesBilinearOnRectangle() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 100, y: 100),
        topRight: CGPoint(x: 500, y: 100),
        bottomRight: CGPoint(x: 500, y: 500),
        bottomLeft: CGPoint(x: 100, y: 500)
    )
    for i in 0...8 {
        let t = CGFloat(i) / 8
        let p = quad.perspectiveMapped(u: t, v: 0.375)
        let b = quad.interpolated(u: t, v: 0.375)
        #expect(abs(p.x - b.x) < 0.01)
        #expect(abs(p.y - b.y) < 0.01)
    }
}

@Test func squareContainingCameraPointUsesPerspectiveGrid() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 300, y: 80),
        topRight: CGPoint(x: 500, y: 80),
        bottomRight: CGPoint(x: 900, y: 700),
        bottomLeft: CGPoint(x: 100, y: 700)
    )
    // Center of file 0 / rank-from-top 0 in perspective UV.
    let sample = quad.perspectiveMapped(u: 1.0 / 16.0, v: 1.0 / 16.0)
    let square = quad.square(containingCameraPoint: sample, orientation: .whiteAtBottom)
    #expect(square?.algebraic == "a8")
}
