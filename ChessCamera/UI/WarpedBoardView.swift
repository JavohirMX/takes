import SwiftUI
import UIKit

struct WarpedBoardView: View {
    var image: CGImage?
    var orientation: BoardOrientation
    var classes: [ChessSquare: PieceClass] = [:]
    var grid: RefinedBoardGrid?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let image {
                    Image(uiImage: UIImage(cgImage: image))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side, height: side)
                } else {
                    Theme.surfaceMuted
                        .frame(width: side, height: side)
                    Text("Line up the four corners")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(16)
                }
                grid(side: side)
                labels(side: side)
                if !classes.isEmpty {
                    pieces(side: side)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Top-down chessboard")
    }

    private func grid(side: CGFloat) -> some View {
        Canvas { context, size in
            var path = Path()
            if let grid {
                for i in 0...8 {
                    path.move(to: grid.viewPoint(row: i, col: 0, side: size.width))
                    path.addLine(to: grid.viewPoint(row: i, col: 8, side: size.width))
                    path.move(to: grid.viewPoint(row: 0, col: i, side: size.width))
                    path.addLine(to: grid.viewPoint(row: 8, col: i, side: size.width))
                }
            } else {
                let cell = size.width / 8
                for i in 0...8 {
                    let t = CGFloat(i) * cell
                    path.move(to: CGPoint(x: t, y: 0))
                    path.addLine(to: CGPoint(x: t, y: size.height))
                    path.move(to: CGPoint(x: 0, y: t))
                    path.addLine(to: CGPoint(x: size.width, y: t))
                }
            }
            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    private func pieces(side: CGFloat) -> some View {
        let cell = side / 8
        return ZStack {
            ForEach(0..<8, id: \.self) { rankFromImageTop in
                ForEach(0..<8, id: \.self) { fileIndex in
                    let square = GridSampler.square(
                        fileIndex: fileIndex,
                        rankFromImageTop: rankFromImageTop,
                        orientation: orientation
                    )
                    if let piece = classes[square], piece != .empty {
                        let center = grid?.cellCenter(
                            fileIndex: fileIndex,
                            rankFromImageTop: rankFromImageTop,
                            side: side
                        ) ?? CGPoint(
                            x: cell * CGFloat(fileIndex) + cell / 2,
                            y: cell * CGFloat(rankFromImageTop) + cell / 2
                        )
                        PieceView(piece: piece, size: cell * 0.78)
                            .shadow(color: .black.opacity(0.45), radius: 1)
                            .position(center)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func labels(side: CGFloat) -> some View {
        let filesRunHorizontally: Bool = {
            switch orientation {
            case .whiteAtBottom, .whiteAtTop: true
            case .whiteAtLeft, .whiteAtRight: false
            }
        }()
        let cell = side / 8
        return ZStack {
            ForEach(0..<8, id: \.self) { i in
                let bottomSquare = GridSampler.square(
                    fileIndex: i,
                    rankFromImageTop: 7,
                    orientation: orientation
                )
                let leftSquare = GridSampler.square(
                    fileIndex: 0,
                    rankFromImageTop: i,
                    orientation: orientation
                )
                let bottomText = filesRunHorizontally
                    ? String(bottomSquare.algebraic.prefix(1))
                    : "\(bottomSquare.rank + 1)"
                let leftText = filesRunHorizontally
                    ? "\(leftSquare.rank + 1)"
                    : String(leftSquare.algebraic.prefix(1))
                let fileCenter = grid?.cellCenter(fileIndex: i, rankFromImageTop: 7, side: side)
                    ?? CGPoint(x: cell * CGFloat(i) + cell / 2, y: side - 10)
                let rankCenter = grid?.cellCenter(fileIndex: 0, rankFromImageTop: i, side: side)
                    ?? CGPoint(x: 10, y: cell * CGFloat(i) + cell / 2)
                Text(bottomText)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 4)
                    .background(Theme.accent.opacity(0.85), in: Capsule())
                    .position(x: fileCenter.x, y: side - 10)
                Text(leftText)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 4)
                    .background(Theme.accent.opacity(0.85), in: Capsule())
                    .position(x: 10, y: rankCenter.y)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}
