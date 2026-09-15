import CoreGraphics
import CoreVideo
import Foundation

/// Coarse ML/Vision box → padded warp → OpenCV 8×8 grid → warp from the playing squares.
enum PaddedBoardRefiner {
    static let borderFraction: CGFloat = 0.15
    /// Minimum grid likeness for a chessboardCorners snap.
    static let scoreFloor: CGFloat = 0.2
    /// Stricter floor when only Hough lattice succeeded (more false positives).
    static let houghScoreFloor: CGFloat = 0.35
    /// Allow a small score drop vs the seed warp when OpenCV tightens the crop.
    static let scoreEpsilon: CGFloat = 0.05

    struct Result: Sendable {
        var snappedQuad: Quadrilateral
        nonisolated(unsafe) var tightWarp: CGImage?
        var grid: RefinedBoardGrid
        var source: OpenCVGridRefiner.Source
        var snappedScore: CGFloat
        var seedScore: CGFloat
    }

    static func refine(
        quad: Quadrilateral,
        buffer: CVPixelBuffer,
        bufferSize: CGSize,
        borderFraction: CGFloat = borderFraction
    ) -> Result? {
        let search = quad.expandedIfFits(by: borderFraction, in: bufferSize)
        if let result = snap(from: search, buffer: buffer) {
            return result
        }
        if search != quad, let result = snap(from: quad, buffer: buffer) {
            return result
        }
        return nil
    }

    /// Accept when snapped warp looks at least as chessboard-like as the seed (within ε).
    static func passesScoreGate(
        seedScore: CGFloat,
        snappedScore: CGFloat,
        source: OpenCVGridRefiner.Source
    ) -> Bool {
        let floor = source == .hough ? houghScoreFloor : scoreFloor
        guard snappedScore >= floor else { return false }
        return snappedScore >= seedScore - scoreEpsilon
    }

    private static func snap(from searchQuad: Quadrilateral, buffer: CVPixelBuffer) -> Result? {
        guard let warped = BoardWarper.warp(buffer, quad: searchQuad, size: 512),
              let detailed = OpenCVGridRefiner.refineDetailed(warped.squareImage),
              detailed.grid.isMonotonic else {
            return nil
        }
        let seedScore = ChessboardGridScore.score(cgImage: warped.squareImage)
        let snapped = detailed.grid.cameraQuad(mappingWith: searchQuad)
        guard let rewarped = BoardWarper.warp(buffer, quad: snapped, size: 512) else {
            return nil
        }
        let snappedScore = ChessboardGridScore.score(cgImage: rewarped.squareImage)
        guard passesScoreGate(
            seedScore: seedScore,
            snappedScore: snappedScore,
            source: detailed.source
        ) else {
            return nil
        }
        let grid: RefinedBoardGrid
        if let second = OpenCVGridRefiner.refine(rewarped.squareImage), second.isMonotonic {
            grid = second
        } else {
            grid = .even(imageSize: CGFloat(rewarped.squareImage.width))
        }
        return Result(
            snappedQuad: snapped,
            tightWarp: rewarped.squareImage,
            grid: grid,
            source: detailed.source,
            snappedScore: snappedScore,
            seedScore: seedScore
        )
    }
}
