import SwiftUI

/// Premium chess arrow overlay (straight or L-shaped for knights) with clean geometry.
struct BoardArrowOverlay: View {
    var from: ChessSquare
    var to: ChessSquare
    var side: CGFloat
    var orientation: BoardOrientation = .whiteAtBottom
    var isBestMove: Bool = true

    var body: some View {
        let squareSize = side / 8
        let start = center(of: from, squareSize: squareSize)
        let end = center(of: to, squareSize: squareSize)

        Canvas { context, _ in
            let dFile = abs(to.file - from.file)
            let dRank = abs(to.rank - from.rank)
            let isKnight = (dFile == 1 && dRank == 2) || (dFile == 2 && dRank == 1)

            let arrowColor = isBestMove
                ? Color(red: 0.10, green: 0.85, blue: 0.85) // Bright Cyan / Teal for best move
                : Color(red: 0.98, green: 0.76, blue: 0.22) // Amber for played move
            let opacity: Double = isBestMove ? 0.95 : 0.85
            let lineWidth = max(5.0, squareSize * 0.17)
            let headLength = max(14, squareSize * 0.38)

            var points: [CGPoint] = [start]
            var finalAngle: CGFloat = 0

            if isKnight {
                // L-shape: 2 squares first, then 1 square turn
                let midSquare: ChessSquare
                if dRank == 2 {
                    midSquare = ChessSquare(file: from.file, rank: to.rank)
                } else {
                    midSquare = ChessSquare(file: to.file, rank: from.rank)
                }
                let midPoint = center(of: midSquare, squareSize: squareSize)
                points.append(midPoint)
                points.append(end)
                finalAngle = atan2(end.y - midPoint.y, end.x - midPoint.x)
            } else {
                points.append(end)
                finalAngle = atan2(end.y - start.y, end.x - start.x)
            }

            // The shaft stops at the base of the arrowhead to avoid poking past the tip
            let shaftEnd = CGPoint(
                x: end.x - (headLength * 0.82) * cos(finalAngle),
                y: end.y - (headLength * 0.82) * sin(finalAngle)
            )

            // Draw shaft
            var shaftPath = Path()
            shaftPath.move(to: points[0])
            if points.count == 3 {
                // Smooth rounded corner for knight turn
                shaftPath.addArc(
                    tangent1End: points[1],
                    tangent2End: shaftEnd,
                    radius: squareSize * 0.22
                )
                shaftPath.addLine(to: shaftEnd)
            } else {
                shaftPath.addLine(to: shaftEnd)
            }

            // High-contrast dark backing outline
            context.stroke(
                shaftPath,
                with: .color(Color.black.opacity(0.4)),
                style: StrokeStyle(lineWidth: lineWidth + 2.5, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                shaftPath,
                with: .color(arrowColor.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

            // Draw arrowhead chevron
            let wingAngle: CGFloat = .pi / 6.5
            let wing1 = CGPoint(
                x: end.x - headLength * cos(finalAngle - wingAngle),
                y: end.y - headLength * sin(finalAngle - wingAngle)
            )
            let wing2 = CGPoint(
                x: end.x - headLength * cos(finalAngle + wingAngle),
                y: end.y - headLength * sin(finalAngle + wingAngle)
            )
            let notch = CGPoint(
                x: end.x - (headLength * 0.72) * cos(finalAngle),
                y: end.y - (headLength * 0.72) * sin(finalAngle)
            )

            var headPath = Path()
            headPath.move(to: end)
            headPath.addLine(to: wing1)
            headPath.addLine(to: notch)
            headPath.addLine(to: wing2)
            headPath.closeSubpath()

            // Backing outline for arrowhead
            context.stroke(
                headPath,
                with: .color(Color.black.opacity(0.4)),
                style: StrokeStyle(lineWidth: 2.0, lineJoin: .round)
            )

            context.fill(headPath, with: .color(arrowColor.opacity(opacity)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func center(of square: ChessSquare, squareSize: CGFloat) -> CGPoint {
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
