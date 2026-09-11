import CoreGraphics
import Foundation

struct SquareCrop: Sendable, Identifiable {
    var square: ChessSquare
    nonisolated(unsafe) var image: CGImage
    var id: String { square.algebraic }
}

enum GridSampler {
    /// Crop rectangle for one square in a square warped board image.
    /// `rankFromImageTop` is 0 at the top of the image and 7 at the bottom.
    /// `inset` is a fraction of the cell size (e.g. 0.12) shrunk inward from each edge.
    static func rect(
        fileIndex: Int,
        rankFromImageTop: Int,
        imageSize: CGFloat,
        inset: CGFloat
    ) -> CGRect {
        let cell = imageSize / 8
        let origin = CGPoint(
            x: CGFloat(fileIndex) * cell,
            y: CGFloat(rankFromImageTop) * cell
        )
        let square = CGRect(origin: origin, size: CGSize(width: cell, height: cell))
        guard inset > 0 else { return square }
        return square.insetBy(dx: cell * inset, dy: cell * inset)
    }

    /// Maps a camera-space grid index to an algebraic square after orientation.
    ///
    /// - `whiteAtBottom`: image bottom-left is a1 (file 0 left, rank 1 at image bottom).
    /// - `whiteAtLeft`: image top-left is a1 (files run top→bottom).
    /// - `whiteAtTop`: image top-right is a1 (files mirrored, rank 1 at image top).
    /// - `whiteAtRight`: image bottom-right is a1 (files run bottom→top).
    static func square(
        fileIndex: Int,
        rankFromImageTop: Int,
        orientation: BoardOrientation
    ) -> ChessSquare {
        orientation.square(fileIndex: fileIndex, rankFromImageTop: rankFromImageTop)
    }

    /// Inverse of `square(fileIndex:rankFromImageTop:orientation:)`.
    static func imageIndices(
        for square: ChessSquare,
        orientation: BoardOrientation
    ) -> (fileIndex: Int, rankFromImageTop: Int) {
        orientation.imageIndices(for: square)
    }

    /// Maps a pixel in a square warped board (top-left origin) to an algebraic square.
    /// Points on the far right/bottom edge clamp into the last file/rank.
    static func square(
        containing point: CGPoint,
        imageSize: CGFloat,
        orientation: BoardOrientation
    ) -> ChessSquare? {
        guard imageSize > 0,
              point.x >= 0, point.y >= 0,
              point.x <= imageSize, point.y <= imageSize else { return nil }
        let cell = imageSize / 8
        let fileIndex = min(7, Int(point.x / cell))
        let rankFromImageTop = min(7, Int(point.y / cell))
        return square(
            fileIndex: fileIndex,
            rankFromImageTop: rankFromImageTop,
            orientation: orientation
        )
    }

    /// 64 square crops from a square warped board. Inset avoids neighboring pieces and gutters.
    static func crops(
        from warped: CGImage,
        orientation: BoardOrientation,
        inset: CGFloat = 0.12
    ) -> [SquareCrop] {
        let imageSize = CGFloat(min(warped.width, warped.height))
        var crops: [SquareCrop] = []
        crops.reserveCapacity(64)
        for rankFromImageTop in 0..<8 {
            for fileIndex in 0..<8 {
                let cropRect = rect(
                    fileIndex: fileIndex,
                    rankFromImageTop: rankFromImageTop,
                    imageSize: imageSize,
                    inset: inset
                ).integral
                guard cropRect.width >= 1, cropRect.height >= 1,
                      let tile = warped.cropping(to: cropRect) else { continue }
                crops.append(
                    SquareCrop(
                        square: square(
                            fileIndex: fileIndex,
                            rankFromImageTop: rankFromImageTop,
                            orientation: orientation
                        ),
                        image: tile
                    )
                )
            }
        }
        return crops
    }
}
