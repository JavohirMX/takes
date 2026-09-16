import SwiftUI

struct DigitalBoardView: View {
    var fen: String
    /// Display mapping. Call sites should keep the default so the diagram stays White-at-bottom.
    var orientation: BoardOrientation = .whiteAtBottom
    var lastMove: (from: ChessSquare, to: ChessSquare)?
    /// Optional engine best-move arrow (from, to).
    var bestMove: BoardArrow?
    var selected: ChessSquare?
    var interactive = false
    var showsCoordinates = true
    var styleOverride: BoardStyle?
    var onTap: ((ChessSquare) -> Void)?

    @AppStorage(BoardAppearance.styleKey) private var styleRaw = BoardAppearance.defaultStyle.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrivalPulse = false

    private var style: BoardStyle {
        styleOverride ?? BoardStyle(rawValue: styleRaw) ?? BoardAppearance.defaultStyle
    }

    private var pieces: [ChessSquare: PieceClass] {
        FenCodec.parsePieces(fen)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let squareSize = side / 8
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { displayRank in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { displayFile in
                                let square = mappedSquare(file: displayFile, rankFromTop: displayRank)
                                let isLight = (square.file + square.rank).isMultiple(of: 2) == false
                                let piece = pieces[square]
                                ZStack {
                                    (isLight ? style.light : style.dark)
                                    if isHighlighted(square) {
                                        style.lastMove
                                    }
                                    if selected == square {
                                        Theme.accent.opacity(0.35)
                                    }
                                    if showsCoordinates {
                                        coordinates(
                                            square: square,
                                            displayFile: displayFile,
                                            displayRank: displayRank,
                                            isLight: isLight,
                                            squareSize: squareSize
                                        )
                                    }
                                    if let piece, piece != .empty {
                                        PieceView(piece: piece, size: squareSize * 0.88)
                                            .scaleEffect(arrivalScale(for: square))
                                            .opacity(arrivalOpacity(for: square))
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

                if let bestMove {
                    BoardArrowOverlay(
                        from: bestMove.from,
                        to: bestMove.to,
                        side: side,
                        orientation: orientation
                    )
                    .frame(width: side, height: side)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(style.frame, lineWidth: 1)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Digital chessboard")
        .onChange(of: arrivalKey) { _, _ in
            pulseArrival()
        }
        .onAppear {
            pulseArrival()
        }
    }

    private var arrivalKey: String {
        guard let lastMove else { return fen }
        return "\(fen)|\(lastMove.from.algebraic)\(lastMove.to.algebraic)"
    }

    private func pulseArrival() {
        guard lastMove != nil, !reduceMotion else {
            arrivalPulse = false
            return
        }
        arrivalPulse = true
        withAnimation(.easeOut(duration: 0.2)) {
            arrivalPulse = false
        }
    }

    private func arrivalScale(for square: ChessSquare) -> CGFloat {
        lastMove?.to == square && arrivalPulse ? 0.86 : 1
    }

    private func arrivalOpacity(for square: ChessSquare) -> Double {
        lastMove?.to == square && arrivalPulse ? 0.55 : 1
    }

    @ViewBuilder
    private func coordinates(
        square: ChessSquare,
        displayFile: Int,
        displayRank: Int,
        isLight: Bool,
        squareSize: CGFloat
    ) -> some View {
        let ink = isLight ? style.coordinateOnLight : style.coordinateOnDark
        let font = Font.system(size: max(8, squareSize * 0.18), weight: .semibold, design: .monospaced)
        if displayRank == 7 {
            Text(String(square.algebraic.prefix(1)))
                .font(font)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(2)
                .accessibilityHidden(true)
        }
        if displayFile == 0 {
            Text("\(square.rank + 1)")
                .font(font)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(2)
                .accessibilityHidden(true)
        }
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

#Preview("Tournament") {
    DigitalBoardView(fen: FenCodec.standard, styleOverride: .tournament)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Walnut") {
    DigitalBoardView(fen: FenCodec.standard, styleOverride: .walnut)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Blue") {
    DigitalBoardView(fen: FenCodec.standard, styleOverride: .blue)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Slate") {
    DigitalBoardView(fen: FenCodec.standard, styleOverride: .slate)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Confirm interactive") {
    DigitalBoardView(fen: FenCodec.standard, interactive: true, styleOverride: .tournament)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("History thumbnail") {
    DigitalBoardView(fen: FenCodec.standard, showsCoordinates: false, styleOverride: .tournament)
        .frame(width: 72, height: 72)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
