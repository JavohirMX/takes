import CoreGraphics
import Foundation
import Testing
@testable import Takes

@Test func evenGridMapsA1CenterWhenWhiteAtBottom() {
    let grid = RefinedBoardGrid.even(imageSize: 512)
    let a1 = grid.square(
        containingWarped: CGPoint(x: 32, y: 480),
        orientation: .whiteAtBottom
    )
    #expect(a1?.algebraic == "a1")
}

@Test func unevenLatticeStillMapsA1() {
    var points: [CGPoint] = []
    // Slightly stretched files (wider on the right), even ranks.
    let ys: [CGFloat] = (0...8).map { CGFloat($0) * 64 }
    let xs: [CGFloat] = [0, 58, 120, 184, 250, 318, 388, 456, 512]
    for row in 0...8 {
        for col in 0...8 {
            points.append(CGPoint(x: xs[col], y: ys[row]))
        }
    }
    let grid = RefinedBoardGrid(imageSize: 512, points: points)
    let a1 = grid.square(
        containingWarped: CGPoint(x: 29, y: 480),
        orientation: .whiteAtBottom
    )
    #expect(a1?.algebraic == "a1")
    let occupancy = PieceDetection.occupancy(
        from: [
            PieceDetection.Box(
                id: 0,
                piece: .blackQueen,
                confidence: 0.9,
                // Center anchor must land inside uneven a1 (x 0…58, y 448…512).
                bufferRect: CGRect(x: 9, y: 448, width: 40, height: 60)
            )
        ],
        quad: Quadrilateral(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 512, y: 0),
            bottomRight: CGPoint(x: 512, y: 512),
            bottomLeft: CGPoint(x: 0, y: 512)
        ),
        orientation: .whiteAtBottom,
        grid: grid
    )
    #expect(occupancy.occupied(ChessSquare(file: 0, rank: 0)))
}

@Test func extrapolateInnerCornersMakesNineByNine() {
    var inner: [CGPoint] = []
    for row in 1...7 {
        for col in 1...7 {
            inner.append(CGPoint(x: CGFloat(col) * 64, y: CGFloat(row) * 64))
        }
    }
    let gridPoints = OpenCVGridRefiner.extrapolate9x9(fromInner7x7: inner)
    #expect(gridPoints?.count == 81)
    #expect(abs((gridPoints?[0].x ?? -1) - 0) < 1)
    #expect(abs((gridPoints?[80].x ?? -1) - 512) < 1)
    #expect(abs((gridPoints?[80].y ?? -1) - 512) < 1)
}

@Test func houghRhoClusterPicksNineEvenLines() {
    var rhos: [Float] = []
    for i in 0...8 {
        let base = Float(i) * 64
        rhos.append(base)
        rhos.append(base + 1.5)
        rhos.append(base - 1.2)
    }
    rhos.append(200)
    let clustered = OpenCVGridRefiner.cluster(rhos: rhos, expected: 9, imageSize: 512)
    #expect(clustered?.count == 9)
    #expect(abs((clustered?.first ?? -1) - 0) < 3)
    #expect(abs((clustered?.last ?? -1) - 512) < 3)
}

@Test func opencvRefinesFullBleedCheckerboard() throws {
    let image = try makeInsetCheckerboard(size: 512, inset: 0)
    let grid = try #require(OpenCVGridRefiner.refine(image))
    #expect(grid.points.count == 81)
    #expect(grid.isMonotonic)
    for i in 0...8 {
        let expected = CGFloat(i) * 64
        #expect(abs(grid.point(row: 0, col: i).x - expected) < 8)
        #expect(abs(grid.point(row: i, col: 0).y - expected) < 8)
    }
    let a1 = grid.square(
        containingWarped: CGPoint(x: 32, y: 480),
        orientation: .whiteAtBottom
    )
    #expect(a1?.algebraic == "a1")
}

@Test func opencvRefinesInsetCheckerboard() throws {
    let image = try makeInsetCheckerboard(size: 512, inset: 32)
    let grid = try #require(OpenCVGridRefiner.refine(image))
    #expect(grid.points.count == 81)
    #expect(grid.isMonotonic)
    #expect(abs(grid.point(row: 0, col: 0).x - 32) < 12)
    #expect(abs(grid.point(row: 8, col: 8).y - 480) < 12)
    let a1 = grid.square(
        containingWarped: CGPoint(x: 32 + 28, y: 512 - 32 - 28),
        orientation: .whiteAtBottom
    )
    #expect(a1?.algebraic == "a1")
}

@Test func refineNilFallsBackToEvenGridMapping() throws {
    let image = try makeFlatGray(size: 512, gray: 180)
    #expect(OpenCVGridRefiner.refine(image) == nil)
    let grid = RefinedBoardGrid.even(imageSize: 512)
    let a1 = grid.square(
        containingWarped: CGPoint(x: 32, y: 480),
        orientation: .whiteAtBottom
    )
    #expect(a1?.algebraic == "a1")
}

private func makeInsetCheckerboard(size: Int, inset: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 180, count: size * size * 4)
    let inner = size - inset * 2
    let cell = inner / 8
    for y in 0..<size {
        for x in 0..<size {
            let i = (y * size + x) * 4
            var v: UInt8 = 180
            if x >= inset, y >= inset, x < inset + 8 * cell, y < inset + 8 * cell {
                let file = (x - inset) / cell
                let rank = (y - inset) / cell
                let dark = ((file + rank) % 2) == 0
                v = dark ? 30 : 220
            }
            bytes[i] = v
            bytes[i + 1] = v
            bytes[i + 2] = v
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

private func makeFlatGray(size: Int, gray: UInt8) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for i in stride(from: 0, to: bytes.count, by: 4) {
        bytes[i] = gray
        bytes[i + 1] = gray
        bytes[i + 2] = gray
        bytes[i + 3] = 255
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
