import CoreGraphics

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
    /// - `whiteAtTop`: image top is rank 1 and files are mirrored (h-file on the left).
    static func square(
        fileIndex: Int,
        rankFromImageTop: Int,
        orientation: BoardOrientation
    ) -> ChessSquare {
        switch orientation {
        case .whiteAtBottom:
            ChessSquare(file: fileIndex, rank: 7 - rankFromImageTop)
        case .whiteAtTop:
            ChessSquare(file: 7 - fileIndex, rank: rankFromImageTop)
        }
    }
}
