import SwiftUI
import UIKit

struct WarpedBoardView: View {
    var image: CGImage?
    var orientation: BoardOrientation
    var classes: [ChessSquare: PieceClass] = [:]

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
            let cell = size.width / 8
            var path = Path()
            for i in 0...8 {
                let t = CGFloat(i) * cell
                path.move(to: CGPoint(x: t, y: 0))
                path.addLine(to: CGPoint(x: t, y: size.height))
                path.move(to: CGPoint(x: 0, y: t))
                path.addLine(to: CGPoint(x: size.width, y: t))
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
                        Text(piece.glyph)
                            .font(.system(size: cell * 0.62))
                            .foregroundStyle(piece.isWhite ? Color.white : Color.black)
                            .shadow(color: .black.opacity(0.45), radius: 1)
                            .position(
                                x: cell * CGFloat(fileIndex) + cell / 2,
                                y: cell * CGFloat(rankFromImageTop) + cell / 2
                            )
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func labels(side: CGFloat) -> some View {
        let files = orientation == .whiteAtBottom ? Array("abcdefgh") : Array("hgfedcba")
        let ranks = orientation == .whiteAtBottom ? [8, 7, 6, 5, 4, 3, 2, 1] : [1, 2, 3, 4, 5, 6, 7, 8]
        let cell = side / 8
        return ZStack {
            ForEach(0..<8, id: \.self) { i in
                Text(String(files[i]))
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 4)
                    .background(Theme.accent.opacity(0.85), in: Capsule())
                    .position(x: cell * CGFloat(i) + cell / 2, y: side - 10)
                Text("\(ranks[i])")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 4)
                    .background(Theme.accent.opacity(0.85), in: Capsule())
                    .position(x: 10, y: cell * CGFloat(i) + cell / 2)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}
