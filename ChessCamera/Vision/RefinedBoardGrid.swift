import CoreGraphics
import Foundation

/// 9×9 lattice in warped-board pixels (row-major, row 0 = image top).
struct RefinedBoardGrid: Equatable, Sendable {
    var imageSize: CGFloat
    var points: [CGPoint]

    static let lineCount = 9
    static let pointCount = lineCount * lineCount

    static func even(imageSize: CGFloat) -> RefinedBoardGrid {
        var points: [CGPoint] = []
        points.reserveCapacity(pointCount)
        let step = imageSize / 8
        for row in 0..<lineCount {
            for col in 0..<lineCount {
                points.append(CGPoint(x: CGFloat(col) * step, y: CGFloat(row) * step))
            }
        }
        return RefinedBoardGrid(imageSize: imageSize, points: points)
    }

    func point(row: Int, col: Int) -> CGPoint {
        points[row * Self.lineCount + col]
    }

    /// Map warped lattice corners back into camera-buffer space via the current outer quad.
    /// Uses perspective mapping to match `BoardWarper` / `CIFilter.perspectiveCorrection`.
    func cameraQuad(mappingWith quad: Quadrilateral) -> Quadrilateral {
        func camera(_ row: Int, _ col: Int) -> CGPoint {
            let p = point(row: row, col: col)
            return quad.perspectiveMapped(u: p.x / imageSize, v: p.y / imageSize)
        }
        return Quadrilateral(
            topLeft: camera(0, 0),
            topRight: camera(0, 8),
            bottomRight: camera(8, 8),
            bottomLeft: camera(8, 0)
        )
    }

    func viewPoint(row: Int, col: Int, side: CGFloat) -> CGPoint {
        let p = point(row: row, col: col)
        guard imageSize > 0 else { return .zero }
        return CGPoint(x: p.x / imageSize * side, y: p.y / imageSize * side)
    }

    func cellCenter(fileIndex: Int, rankFromImageTop: Int, side: CGFloat) -> CGPoint {
        let a = viewPoint(row: rankFromImageTop, col: fileIndex, side: side)
        let b = viewPoint(row: rankFromImageTop, col: fileIndex + 1, side: side)
        let c = viewPoint(row: rankFromImageTop + 1, col: fileIndex + 1, side: side)
        let d = viewPoint(row: rankFromImageTop + 1, col: fileIndex, side: side)
        return CGPoint(
            x: (a.x + b.x + c.x + d.x) / 4,
            y: (a.y + b.y + c.y + d.y) / 4
        )
    }

    func square(containingWarped warped: CGPoint, orientation: BoardOrientation) -> ChessSquare? {
        for row in 0..<8 {
            for col in 0..<8 {
                let tl = point(row: row, col: col)
                let tr = point(row: row, col: col + 1)
                let br = point(row: row + 1, col: col + 1)
                let bl = point(row: row + 1, col: col)
                let minX = min(min(tl.x, tr.x), min(br.x, bl.x))
                let maxX = max(max(tl.x, tr.x), max(br.x, bl.x))
                let minY = min(min(tl.y, tr.y), min(br.y, bl.y))
                let maxY = max(max(tl.y, tr.y), max(br.y, bl.y))
                if warped.x >= minX, warped.x <= maxX, warped.y >= minY, warped.y <= maxY {
                    return GridSampler.square(
                        fileIndex: col,
                        rankFromImageTop: row,
                        orientation: orientation
                    )
                }
            }
        }
        return nil
    }

    var isMonotonic: Bool {
        guard points.count == Self.pointCount, imageSize > 8 else { return false }
        let minStep = imageSize / 24
        let maxStep = imageSize / 4
        for row in 0..<Self.lineCount {
            for col in 0..<8 {
                let delta = point(row: row, col: col + 1).x - point(row: row, col: col).x
                if delta < minStep || delta > maxStep { return false }
            }
        }
        for col in 0..<Self.lineCount {
            for row in 0..<8 {
                let delta = point(row: row + 1, col: col).y - point(row: row, col: col).y
                if delta < minStep || delta > maxStep { return false }
            }
        }
        return true
    }
}
