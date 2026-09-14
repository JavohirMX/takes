import CoreGraphics
import CoreVideo
import Foundation

/// Coarse ML/Vision box → padded warp → OpenCV 8×8 grid → warp from the playing squares.
enum PaddedBoardRefiner {
    static let borderFraction: CGFloat = 0.15

    struct Result: Sendable {
        var snappedQuad: Quadrilateral
        nonisolated(unsafe) var tightWarp: CGImage?
        var grid: RefinedBoardGrid
    }

    static func refine(
        quad: Quadrilateral,
        buffer: CVPixelBuffer,
        bufferSize: CGSize,
        borderFraction: CGFloat = borderFraction
    ) -> Result? {
        let padded = quad.expanded(by: borderFraction).clamped(to: bufferSize)
        if let result = snap(from: padded, buffer: buffer) {
            return result
        }
        if padded != quad, let result = snap(from: quad, buffer: buffer) {
            return result
        }
        return nil
    }

    private static func snap(from searchQuad: Quadrilateral, buffer: CVPixelBuffer) -> Result? {
        guard let warped = BoardWarper.warp(buffer, quad: searchQuad, size: 512),
              let first = OpenCVGridRefiner.refine(warped.squareImage),
              first.isMonotonic else {
            return nil
        }
        let snapped = first.cameraQuad(mappingWith: searchQuad)
        guard let rewarped = BoardWarper.warp(buffer, quad: snapped, size: 512) else {
            return Result(snappedQuad: snapped, tightWarp: nil, grid: .even(imageSize: 512))
        }
        let grid: RefinedBoardGrid
        if let second = OpenCVGridRefiner.refine(rewarped.squareImage), second.isMonotonic {
            grid = second
        } else {
            grid = .even(imageSize: CGFloat(rewarped.squareImage.width))
        }
        return Result(snappedQuad: snapped, tightWarp: rewarped.squareImage, grid: grid)
    }
}
