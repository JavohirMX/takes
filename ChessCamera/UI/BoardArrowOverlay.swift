import SwiftUI

/// Thin accent arrow from `from` → `to` over an 8×8 board of size `side`.
struct BoardArrowOverlay: View {
    var from: ChessSquare
    var to: ChessSquare
    var side: CGFloat
    var orientation: BoardOrientation = .whiteAtBottom

    var body: some View {
        let squareSize = side / 8
        let start = center(of: from, squareSize: squareSize)
        let end = center(of: to, squareSize: squareSize)
        Canvas { context, _ in
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(
                path,
                with: .color(Theme.accent.opacity(0.85)),
                style: StrokeStyle(lineWidth: max(3, squareSize * 0.12), lineCap: .round)
            )

            // Arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head: CGFloat = max(8, squareSize * 0.28)
            var headPath = Path()
            headPath.move(to: end)
            headPath.addLine(to: CGPoint(
                x: end.x - head * cos(angle - .pi / 7),
                y: end.y - head * sin(angle - .pi / 7)
            ))
            headPath.addLine(to: CGPoint(
                x: end.x - head * cos(angle + .pi / 7),
                y: end.y - head * sin(angle + .pi / 7)
            ))
            headPath.closeSubpath()
            context.fill(headPath, with: .color(Theme.accent.opacity(0.9)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func center(of square: ChessSquare, squareSize: CGFloat) -> CGPoint {
        // DigitalBoardView maps display file/rank with GridSampler + orientation.
        // Invert: find display indices for this square.
        var displayFile = 0
        var displayRank = 0
        for f in 0..<8 {
            for r in 0..<8 {
                let mapped = GridSampler.square(fileIndex: f, rankFromImageTop: r, orientation: orientation)
                if mapped == square {
                    displayFile = f
                    displayRank = r
                }
            }
        }
        return CGPoint(
            x: (CGFloat(displayFile) + 0.5) * squareSize,
            y: (CGFloat(displayRank) + 0.5) * squareSize
        )
    }
}
