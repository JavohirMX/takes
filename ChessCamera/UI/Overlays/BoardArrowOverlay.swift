import SwiftUI

/// Premium chess arrow overlay (straight or L-shaped for knights) with clean, non-blocking translucent geometry.
struct BoardArrowOverlay: View {
    var from: ChessSquare
    var to: ChessSquare
    var side: CGFloat
    var orientation: BoardOrientation = .whiteAtBottom
    var isBestMove: Bool = true

    @AppStorage(ArrowAppearance.colorKey) private var arrowColorRaw = ArrowAppearance.defaultColor.rawValue

    private var activeColor: Color {
        if isBestMove {
            return BestMoveArrowColor(rawValue: arrowColorRaw)?.color ?? ArrowAppearance.defaultColor.color
        } else {
            return Color(red: 0.98, green: 0.76, blue: 0.22) // Amber for played move
        }
    }

    var body: some View {
        let squareSize = side / 8
        let start = center(of: from, squareSize: squareSize)
        let end = center(of: to, squareSize: squareSize)

        Canvas { context, _ in
            let dFile = abs(to.file - from.file)
            let dRank = abs(to.rank - from.rank)
            let isKnight = (dFile == 1 && dRank == 2) || (dFile == 2 && dRank == 1)

            let arrowColor = activeColor
            // Translucent opacity so underlying pieces are clearly visible
            let opacity: Double = isBestMove ? 0.65 : 0.70
            let lineWidth = max(3.5, squareSize * 0.12)
            let headLength = max(11.0, squareSize * 0.30)
            let startOffset = squareSize * 0.24

            var initialAngle: CGFloat = 0
            var finalAngle: CGFloat = 0
            var points: [CGPoint] = []

            if isKnight {
                let midSquare: ChessSquare
                if dRank == 2 {
                    midSquare = ChessSquare(file: from.file, rank: to.rank)
                } else {
                    midSquare = ChessSquare(file: to.file, rank: from.rank)
                }
                let midPoint = center(of: midSquare, squareSize: squareSize)
                initialAngle = atan2(midPoint.y - start.y, midPoint.x - start.x)
                finalAngle = atan2(end.y - midPoint.y, end.x - midPoint.x)

                let adjustedStart = CGPoint(
                    x: start.x + startOffset * cos(initialAngle),
                    y: start.y + startOffset * sin(initialAngle)
                )
                points.append(adjustedStart)
                points.append(midPoint)
                points.append(end)
            } else {
                initialAngle = atan2(end.y - start.y, end.x - start.x)
                finalAngle = initialAngle

                let adjustedStart = CGPoint(
                    x: start.x + startOffset * cos(initialAngle),
                    y: start.y + startOffset * sin(initialAngle)
                )
                points.append(adjustedStart)
                points.append(end)
            }

            // Shaft terminates at the base of the arrowhead chevron
            let shaftEnd = CGPoint(
                x: end.x - (headLength * 0.85) * cos(finalAngle),
                y: end.y - (headLength * 0.85) * sin(finalAngle)
            )

            // Draw shaft path
            var shaftPath = Path()
            shaftPath.move(to: points[0])
            if points.count == 3 {
                shaftPath.addArc(
                    tangent1End: points[1],
                    tangent2End: shaftEnd,
                    radius: squareSize * 0.24
                )
                shaftPath.addLine(to: shaftEnd)
            } else {
                shaftPath.addLine(to: shaftEnd)
            }

            // Subtle, soft backing outline for contrast across dark/light squares
            context.stroke(
                shaftPath,
                with: .color(Color.black.opacity(0.20)),
                style: StrokeStyle(lineWidth: lineWidth + 2.0, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                shaftPath,
                with: .color(arrowColor.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

            // Draw sleek arrowhead chevron
            let wingAngle: CGFloat = .pi / 6.0
            let wing1 = CGPoint(
                x: end.x - headLength * cos(finalAngle - wingAngle),
                y: end.y - headLength * sin(finalAngle - wingAngle)
            )
            let wing2 = CGPoint(
                x: end.x - headLength * cos(finalAngle + wingAngle),
                y: end.y - headLength * sin(finalAngle + wingAngle)
            )
            let notch = CGPoint(
                x: end.x - (headLength * 0.75) * cos(finalAngle),
                y: end.y - (headLength * 0.75) * sin(finalAngle)
            )

            var headPath = Path()
            headPath.move(to: end)
            headPath.addLine(to: wing1)
            headPath.addLine(to: notch)
            headPath.addLine(to: wing2)
            headPath.closeSubpath()

            // Subtle outline for arrowhead
            context.stroke(
                headPath,
                with: .color(Color.black.opacity(0.20)),
                style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
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
