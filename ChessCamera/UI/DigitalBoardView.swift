import SwiftUI

struct DigitalBoardView: View {
    var fen: String
    var orientation: BoardOrientation = .whiteAtBottom
    var lastMove: (from: ChessSquare, to: ChessSquare)?
    var selected: ChessSquare?
    var interactive = false
    var onTap: ((ChessSquare) -> Void)?

    private var pieces: [ChessSquare: PieceClass] {
        FenCodec.parsePieces(fen)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let squareSize = side / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { displayRank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { displayFile in
                            let square = mappedSquare(file: displayFile, rankFromTop: displayRank)
                            let isLight = (square.file + square.rank).isMultiple(of: 2) == false
                            let piece = pieces[square]
                            ZStack {
                                (isLight ? Theme.boardLight : Theme.boardDark)
                                if isHighlighted(square) {
                                    Theme.lastMove
                                }
                                if selected == square {
                                    Theme.accent.opacity(0.35)
                                }
                                if let piece, piece != .empty {
                                    Text(piece.glyph)
                                        .font(.system(size: squareSize * 0.72))
                                        .foregroundStyle(piece.isWhite ? Color.white : Color.black)
                                        .shadow(color: piece.isWhite ? .black.opacity(0.35) : .clear, radius: 0.5)
                                }
                            }
                            .frame(width: squareSize, height: squareSize)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard interactive else { return }
                                onTap?(square)
                            }
                            .accessibilityLabel(accessibilityLabel(square: square, piece: piece))
                            .accessibilityAddTraits(interactive ? .isButton : [])
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Digital chessboard")
    }

    private func mappedSquare(file: Int, rankFromTop: Int) -> ChessSquare {
        GridSampler.square(fileIndex: file, rankFromImageTop: rankFromTop, orientation: orientation)
    }

    private func isHighlighted(_ square: ChessSquare) -> Bool {
        guard let lastMove else { return false }
        return square == lastMove.from || square == lastMove.to
    }

    private func accessibilityLabel(square: ChessSquare, piece: PieceClass?) -> String {
        if let piece, piece != .empty {
            "\(square.algebraic), \(piece.accessibilityName)"
        } else {
            "\(square.algebraic), empty"
        }
    }
}

#Preview("Confirm standard") {
    DigitalBoardView(fen: FenCodec.standard)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
