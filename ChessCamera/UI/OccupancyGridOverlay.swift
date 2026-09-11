import SwiftUI

/// Tiny 8×8 occupancy map so you can see whether vision thinks squares changed.
struct OccupancyGridOverlay: View {
    var occupancy: Occupancy
    var orientation: BoardOrientation

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width, size.height) / 8
            for file in 0..<8 {
                for rank in 0..<8 {
                    let square = ChessSquare(file: file, rank: rank)
                    let image = GridSampler.imageIndices(for: square, orientation: orientation)
                    let rect = CGRect(
                        x: CGFloat(image.fileIndex) * cell,
                        y: CGFloat(image.rankFromImageTop) * cell,
                        width: cell,
                        height: cell
                    )
                    let occupied = occupancy.occupied(square)
                    context.fill(
                        Path(ellipseIn: rect.insetBy(dx: cell * 0.28, dy: cell * 0.28)),
                        with: .color(occupied ? Theme.accent.opacity(0.9) : Theme.textSecondary.opacity(0.25))
                    )
                }
            }
        }
        .accessibilityLabel("Occupancy grid")
    }
}
