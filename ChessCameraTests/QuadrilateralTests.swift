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
    #expect(abs(snapped.topLeft.x - original.topLeft.x) < 1)
    #expect(abs(snapped.topLeft.y - original.topLeft.y) < 1)
    #expect(abs(snapped.topRight.x - original.topRight.x) < 1)
    #expect(abs(snapped.topRight.y - original.topRight.y) < 1)
    #expect(abs(snapped.bottomRight.x - original.bottomRight.x) < 1)
    #expect(abs(snapped.bottomRight.y - original.bottomRight.y) < 1)
    #expect(abs(snapped.bottomLeft.x - original.bottomLeft.x) < 1)
    #expect(abs(snapped.bottomLeft.y - original.bottomLeft.y) < 1)

    let uv = padded.uv(containing: original.topLeft, epsilon: 0.02)
    #expect(uv != nil)
    #expect(abs((uv?.x ?? -1) - u0) < 0.02)
    #expect(abs((uv?.y ?? -1) - u0) < 0.02)
}
