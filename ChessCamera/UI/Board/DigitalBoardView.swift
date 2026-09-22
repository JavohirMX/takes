import SwiftUI

struct DigitalBoardView: View {
    var fen: String
    /// Display mapping. Call sites should keep the default so the diagram stays White-at-bottom.
    var orientation: BoardOrientation = .whiteAtBottom
    var lastMove: (from: ChessSquare, to: ChessSquare)?
    /// Optional engine best-move arrow (from, to).
    var bestMove: BoardArrow?
    /// Optional played move arrow.
    var playedMoveArrow: BoardArrow?
    var selected: ChessSquare?
    var legalDestinations: [ChessSquare] = []
    var qualityBadge: MoveQuality?
    var interactive = false
    var showsCoordinates = true
    var styleOverride: BoardStyle?
    var animateMove: Bool = true
    var onTap: ((ChessSquare) -> Void)?

    @AppStorage(BoardAppearance.styleKey) private var styleRaw = BoardAppearance.defaultStyle.rawValue
    @AppStorage(MoveAnimationAppearance.key) private var animationStyleRaw = MoveAnimationAppearance.defaultStyle.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeAnimation: BoardMoveAnimationData? = nil
    @State private var animationProgress: CGFloat = 1.0
    @State private var pulseProgress: CGFloat = 1.0
    @State private var previousFEN: String = ""
    @State private var animationTask: Task<Void, Never>? = nil

    private var style: BoardStyle {
        styleOverride ?? BoardStyle(rawValue: styleRaw) ?? BoardAppearance.defaultStyle
    }

    private var animationStyle: MoveAnimationStyle {
        if reduceMotion || !animateMove { return .none }
        return MoveAnimationStyle(rawValue: animationStyleRaw) ?? MoveAnimationAppearance.defaultStyle
    }

    private var pieces: [ChessSquare: PieceClass] {
        FenCodec.parsePieces(fen)
    }

    private var pulseScale: CGFloat {
        1.0 + (1.0 - pulseProgress) * 0.18
    }

    var body: some View {
        GeometryReader { proxy in
            let side = max(40, min(proxy.size.width, proxy.size.height))
            let squareSize = side / 8
            ZStack {
                // Layer 1 & 2: 8x8 Board Grid and static pieces
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { displayRank in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { displayFile in
                                let square = mappedSquare(file: displayFile, rankFromTop: displayRank)
                                let isLight = (square.file + square.rank).isMultiple(of: 2) == false
                                let piece = pieces[square]
                                let hasPiece = piece != nil && piece != .empty
                                let isDest = legalDestinations.contains(square)

                                ZStack {
                                    // Square base
                                    (isLight ? style.light : style.dark)

                                    // Last move highlight
                                    if isHighlighted(square) {
                                        style.lastMove
                                    }

                                    // Selected square highlight
                                    if selected == square {
                                        Theme.accent.opacity(0.38)
                                    }

                                    // Coordinates
                                    if showsCoordinates {
                                        coordinates(
                                            square: square,
                                            displayFile: displayFile,
                                            displayRank: displayRank,
                                            isLight: isLight,
                                            squareSize: squareSize
                                        )
                                    }

                                    // Piece
                                    if let piece, piece != .empty {
                                        let isHiddenByFlight = (activeAnimation != nil && activeAnimation?.style.isSlide == true && (activeAnimation?.toSquare == square || activeAnimation?.rookToSquare == square))
                                        let isHiddenCapturedPiece = (activeAnimation != nil && activeAnimation?.style.isSlide == true && activeAnimation?.isBackward == true && activeAnimation?.capturedSquare == square)

                                        PieceView(piece: piece, size: squareSize * 0.88)
                                            .scaleEffect(square == activeAnimation?.toSquare && activeAnimation?.style == .pulse ? pulseScale : 1.0)
                                            .opacity((isHiddenByFlight || isHiddenCapturedPiece) ? 0 : 1)
                                    }

                                    // Legal move indicator
                                    if isDest {
                                        if hasPiece {
                                            Circle()
                                                .strokeBorder(Theme.accent.opacity(0.85), lineWidth: max(3, squareSize * 0.10))
                                                .padding(squareSize * 0.08)
                                        } else {
                                            Circle()
                                                .fill(Theme.accent.opacity(0.65))
                                                .frame(width: squareSize * 0.28, height: squareSize * 0.28)
                                        }
                                    }

                                    // Quality badge on the target square of the last move
                                    if let badge = qualityBadge, square == lastMove?.to, !badge.glyph.isEmpty {
                                        qualityBadgeView(badge: badge, squareSize: squareSize)
                                    }
                                }
                                .frame(width: squareSize, height: squareSize)
                                .allowsHitTesting(interactive)
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

                // Layer 3: Flight Animation Overlay (elevated in root ZStack above all rows & squares)
                if let anim = activeAnimation, anim.style.isSlide {
                    // Dissolving or appearing captured piece
                    if let capPiece = anim.capturedPiece, let capPt = anim.capturedPoint {
                        DissolvingCapturedPiece(
                            progress: animationProgress,
                            point: capPt,
                            piece: capPiece,
                            size: squareSize * 0.88,
                            isAppearing: anim.isBackward
                        )
                    }

                    // Castling rook
                    if let rPiece = anim.rookPiece, let rFrom = anim.rookFromPoint, let rTo = anim.rookToPoint {
                        FlyingPieceOverlay(
                            progress: animationProgress,
                            fromPoint: rFrom,
                            toPoint: rTo,
                            piece: rPiece,
                            size: squareSize * 0.88,
                            style: anim.style
                        )
                    }

                    // Primary moving piece
                    FlyingPieceOverlay(
                        progress: animationProgress,
                        fromPoint: anim.fromPoint,
                        toPoint: anim.toPoint,
                        piece: anim.piece,
                        size: squareSize * 0.88,
                        style: anim.style
                    )
                }

                // Layer 4: Played move arrow
                if let playedMoveArrow {
                    BoardArrowOverlay(
                        from: playedMoveArrow.from,
                        to: playedMoveArrow.to,
                        side: side,
                        orientation: orientation,
                        isBestMove: false
                    )
                    .frame(width: side, height: side)
                }

                // Engine best-move arrow
                if let bestMove {
                    BoardArrowOverlay(
                        from: bestMove.from,
                        to: bestMove.to,
                        side: side,
                        orientation: orientation,
                        isBestMove: true
                    )
                    .frame(width: side, height: side)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(style.frame, lineWidth: 1)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: arrivalKey) { _, _ in
                triggerMoveAnimation(side: side)
            }
            .onAppear {
                previousFEN = fen
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Digital chessboard")
    }

    private func qualityBadgeView(badge: MoveQuality, squareSize: CGFloat) -> some View {
        let badgeDiameter = max(18, squareSize * 0.38)
        return ZStack {
            Circle()
                .fill(badge.badgeColor)
                .frame(width: badgeDiameter, height: badgeDiameter)
                .overlay {
                    Circle().strokeBorder(Color.white, lineWidth: 1.5)
                }

            Text(badge.glyph)
                .font(.system(size: max(8, badgeDiameter * 0.52), weight: .black, design: .rounded))
                .foregroundStyle(badge.badgeForeground)
        }
        .shadow(color: .black.opacity(0.45), radius: 2, x: 1, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(2)
        .allowsHitTesting(false)
    }

    private var arrivalKey: String {
        guard let lastMove else { return fen }
        return "\(fen)|\(lastMove.from.algebraic)\(lastMove.to.algebraic)"
    }

    private func squareCenter(square: ChessSquare, side: CGFloat) -> CGPoint {
        let squareSize = side / 8
        let indices = orientation.imageIndices(for: square)
        let x = (CGFloat(indices.fileIndex) + 0.5) * squareSize
        let y = (CGFloat(indices.rankFromImageTop) + 0.5) * squareSize
        return CGPoint(x: x, y: y)
    }

    private func triggerMoveAnimation(side: CGFloat) {
        let oldFEN = previousFEN
        previousFEN = fen

        guard !oldFEN.isEmpty, oldFEN != fen else {
            return
        }

        guard animationStyle != .none, !reduceMotion else {
            return
        }

        let prevPieces = FenCodec.parsePieces(oldFEN)
        let currPieces = FenCodec.parsePieces(fen)

        guard let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prevPieces,
            curr: currPieces,
            oldFEN: oldFEN,
            currFEN: fen,
            hintLastMove: lastMove
        ) else {
            return
        }

        animationTask?.cancel()

        let fromPt = squareCenter(square: transition.fromSquare, side: side)
        let toPt = squareCenter(square: transition.toSquare, side: side)

        var capPt: CGPoint? = nil
        if let capSq = transition.capturedSquare {
            capPt = squareCenter(square: capSq, side: side)
        }

        var rookFromPt: CGPoint? = nil
        var rookToPt: CGPoint? = nil
        if let rFrom = transition.rookFromSquare, let rTo = transition.rookToSquare {
            rookFromPt = squareCenter(square: rFrom, side: side)
            rookToPt = squareCenter(square: rTo, side: side)
        }

        let animData = BoardMoveAnimationData(
            piece: transition.movingPiece,
            fromSquare: transition.fromSquare,
            toSquare: transition.toSquare,
            fromPoint: fromPt,
            toPoint: toPt,
            capturedPiece: transition.capturedPiece,
            capturedPoint: capPt,
            capturedSquare: transition.capturedSquare,
            isBackward: transition.isBackward,
            rookPiece: transition.rookPiece,
            rookFromPoint: rookFromPt,
            rookToPoint: rookToPt,
            rookToSquare: transition.rookToSquare,
            style: animationStyle
        )

        activeAnimation = animData

        if animationStyle == .pulse {
            pulseProgress = 0.0
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                pulseProgress = 1.0
            }
            animationTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                if !Task.isCancelled {
                    activeAnimation = nil
                }
            }
        } else {
            animationProgress = 0.0
            let duration: Double
            let curve: Animation
            switch animationStyle {
            case .smooth:
                duration = 0.22
                curve = .easeInOut(duration: 0.22)
            case .jump:
                duration = 0.26
                curve = .easeInOut(duration: 0.26)
            case .fast:
                duration = 0.12
                curve = .easeOut(duration: 0.12)
            case .pulse, .none:
                duration = 0
                curve = .linear
            }

            withAnimation(curve) {
                animationProgress = 1.0
            }

            animationTask = Task { @MainActor in
                let nanos = UInt64(duration * 1_000_000_000) + 30_000_000
                try? await Task.sleep(nanoseconds: nanos)
                if !Task.isCancelled {
                    activeAnimation = nil
                    animationProgress = 1.0
                }
            }
        }
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

// MARK: - Animation Support Models & Views

struct BoardMoveTransition: Equatable {
    let movingPiece: PieceClass
    let fromSquare: ChessSquare
    let toSquare: ChessSquare
    let isBackward: Bool
    let capturedPiece: PieceClass?
    let capturedSquare: ChessSquare?
    let rookPiece: PieceClass?
    let rookFromSquare: ChessSquare?
    let rookToSquare: ChessSquare?
}

enum BoardMoveTransitionDetector {
    static func activeColor(from fen: String) -> Character {
        let parts = fen.split(separator: " ")
        if parts.count > 1, let firstChar = parts[1].first {
            return firstChar
        }
        return "w"
    }

    private static func isEmptySquare(_ sq: ChessSquare, in board: [ChessSquare: PieceClass]) -> Bool {
        guard let piece = board[sq] else { return true }
        return piece == .empty
    }

    static func detectTransition(
        prev: [ChessSquare: PieceClass],
        curr: [ChessSquare: PieceClass],
        oldFEN: String,
        currFEN: String,
        hintLastMove: (from: ChessSquare, to: ChessSquare)?
    ) -> BoardMoveTransition? {
        let changed = ChessSquare.allCases.filter { (prev[$0] ?? .empty) != (curr[$0] ?? .empty) }
        guard !changed.isEmpty, changed.count <= 4 else {
            return nil
        }

        // 1. Check forward move matching hintLastMove
        if let hint = hintLastMove,
           let movingPiece = curr[hint.to],
           movingPiece != .empty {
            let src = prev[hint.from]
            let isSame = (src == movingPiece)
            let isPromo = (src?.isWhite == movingPiece.isWhite && (src == .whitePawn || src == .blackPawn))
            if isSame || isPromo {
                var capPiece: PieceClass? = nil
                var capSquare: ChessSquare? = nil
                if let targetPrev = prev[hint.to], targetPrev != .empty, targetPrev.isWhite != movingPiece.isWhite {
                    capPiece = targetPrev
                    capSquare = hint.to
                } else if (movingPiece == .whitePawn || movingPiece == .blackPawn) && hint.from.file != hint.to.file && isEmptySquare(hint.to, in: prev) {
                    let epSq = ChessSquare(file: hint.to.file, rank: hint.from.rank)
                    if let epP = prev[epSq], epP != .empty {
                        capPiece = epP
                        capSquare = epSq
                    }
                }

                var rPiece: PieceClass? = nil
                var rFrom: ChessSquare? = nil
                var rTo: ChessSquare? = nil
                if (movingPiece == .whiteKing || movingPiece == .blackKing) && abs(hint.from.file - hint.to.file) == 2 {
                    let rank = hint.from.rank
                    let isKingside = hint.to.file > hint.from.file
                    rFrom = ChessSquare(file: isKingside ? 7 : 0, rank: rank)
                    rTo = ChessSquare(file: isKingside ? 5 : 3, rank: rank)
                    rPiece = movingPiece.isWhite ? .whiteRook : .blackRook
                }

                return BoardMoveTransition(
                    movingPiece: movingPiece,
                    fromSquare: hint.from,
                    toSquare: hint.to,
                    isBackward: false,
                    capturedPiece: capPiece,
                    capturedSquare: capSquare,
                    rookPiece: rPiece,
                    rookFromSquare: rFrom,
                    rookToSquare: rTo
                )
            }
        }

        // 2. Castling (4 squares changed: White/Black Kingside/Queenside)
        if changed.count == 4 {
            let castlingPatterns: [(kStart: ChessSquare, kEnd: ChessSquare, rStart: ChessSquare, rEnd: ChessSquare, king: PieceClass, rook: PieceClass)] = [
                // White Kingside
                (ChessSquare(file: 4, rank: 0), ChessSquare(file: 6, rank: 0), ChessSquare(file: 7, rank: 0), ChessSquare(file: 5, rank: 0), .whiteKing, .whiteRook),
                // White Queenside
                (ChessSquare(file: 4, rank: 0), ChessSquare(file: 2, rank: 0), ChessSquare(file: 0, rank: 0), ChessSquare(file: 3, rank: 0), .whiteKing, .whiteRook),
                // Black Kingside
                (ChessSquare(file: 4, rank: 7), ChessSquare(file: 6, rank: 7), ChessSquare(file: 7, rank: 7), ChessSquare(file: 5, rank: 7), .blackKing, .blackRook),
                // Black Queenside
                (ChessSquare(file: 4, rank: 7), ChessSquare(file: 2, rank: 7), ChessSquare(file: 0, rank: 7), ChessSquare(file: 3, rank: 7), .blackKing, .blackRook)
            ]

            let changedSet = Set(changed)
            for pat in castlingPatterns {
                let patSet: Set<ChessSquare> = [pat.kStart, pat.kEnd, pat.rStart, pat.rEnd]
                if changedSet == patSet {
                    // Forward castling
                    if prev[pat.kStart] == pat.king && curr[pat.kEnd] == pat.king {
                        return BoardMoveTransition(
                            movingPiece: pat.king,
                            fromSquare: pat.kStart,
                            toSquare: pat.kEnd,
                            isBackward: false,
                            capturedPiece: nil,
                            capturedSquare: nil,
                            rookPiece: pat.rook,
                            rookFromSquare: pat.rStart,
                            rookToSquare: pat.rEnd
                        )
                    }
                    // Backward castling (undo)
                    if prev[pat.kEnd] == pat.king && curr[pat.kStart] == pat.king {
                        return BoardMoveTransition(
                            movingPiece: pat.king,
                            fromSquare: pat.kEnd,
                            toSquare: pat.kStart,
                            isBackward: true,
                            capturedPiece: nil,
                            capturedSquare: nil,
                            rookPiece: pat.rook,
                            rookFromSquare: pat.rEnd,
                            rookToSquare: pat.rStart
                        )
                    }
                }
            }
        }

        // 3. En Passant (3 squares changed)
        if changed.count == 3 {
            // Forward en passant:
            for fromSq in changed {
                for toSq in changed where toSq != fromSq {
                    let epSq = changed.first(where: { $0 != fromSq && $0 != toSq })!
                    if let movingP = prev[fromSq], (movingP == .whitePawn || movingP == .blackPawn),
                       curr[toSq] == movingP, isEmptySquare(fromSq, in: curr),
                       let capP = prev[epSq], capP != .empty, capP.isWhite != movingP.isWhite {
                        return BoardMoveTransition(
                            movingPiece: movingP,
                            fromSquare: fromSq,
                            toSquare: toSq,
                            isBackward: false,
                            capturedPiece: capP,
                            capturedSquare: epSq,
                            rookPiece: nil,
                            rookFromSquare: nil,
                            rookToSquare: nil
                        )
                    }
                }
            }
            // Backward en passant (undo):
            for toSq in changed {
                for fromSq in changed where fromSq != toSq {
                    let epSq = changed.first(where: { $0 != fromSq && $0 != toSq })!
                    if let movingP = prev[fromSq], (movingP == .whitePawn || movingP == .blackPawn),
                       curr[toSq] == movingP, isEmptySquare(fromSq, in: curr),
                       let capP = curr[epSq], capP != .empty, capP.isWhite != movingP.isWhite {
                        return BoardMoveTransition(
                            movingPiece: movingP,
                            fromSquare: fromSq,
                            toSquare: toSq,
                            isBackward: true,
                            capturedPiece: capP,
                            capturedSquare: epSq,
                            rookPiece: nil,
                            rookFromSquare: nil,
                            rookToSquare: nil
                        )
                    }
                }
            }
        }

        // 4. Exactly 2 squares changed (Quiet moves, captures, promotions)
        if changed.count == 2 {
            let sqA = changed[0]
            let sqB = changed[1]

            if let trans = evaluateTwoSquareTransition(from: sqA, to: sqB, prev: prev, curr: curr, oldFEN: oldFEN) {
                return trans
            }
            if let trans = evaluateTwoSquareTransition(from: sqB, to: sqA, prev: prev, curr: curr, oldFEN: oldFEN) {
                return trans
            }
        }

        return nil
    }

    private static func evaluateTwoSquareTransition(
        from: ChessSquare,
        to: ChessSquare,
        prev: [ChessSquare: PieceClass],
        curr: [ChessSquare: PieceClass],
        oldFEN: String
    ) -> BoardMoveTransition? {
        guard let pFrom = prev[from], pFrom != .empty,
              let pTo = curr[to], pTo != .empty else {
            return nil
        }

        let isSamePiece = (pFrom == pTo)
        let isPromoForward = (pFrom.isWhite == pTo.isWhite && (pFrom == .whitePawn || pFrom == .blackPawn))
        let isPromoBackward = (pFrom.isWhite == pTo.isWhite && (pTo == .whitePawn || pTo == .blackPawn))

        guard isSamePiece || isPromoForward || isPromoBackward else {
            return nil
        }

        let oldActive = activeColor(from: oldFEN)
        let isForward = (pFrom.isWhite == (oldActive == "w"))

        if isForward {
            var capPiece: PieceClass? = nil
            if let prevTarget = prev[to], prevTarget != .empty, prevTarget.isWhite != pTo.isWhite {
                capPiece = prevTarget
            }
            return BoardMoveTransition(
                movingPiece: pTo,
                fromSquare: from,
                toSquare: to,
                isBackward: false,
                capturedPiece: capPiece,
                capturedSquare: capPiece != nil ? to : nil,
                rookPiece: nil,
                rookFromSquare: nil,
                rookToSquare: nil
            )
        } else {
            var capPiece: PieceClass? = nil
            if let restored = curr[from], restored != .empty, restored.isWhite != pTo.isWhite {
                capPiece = restored
            }
            return BoardMoveTransition(
                movingPiece: pTo,
                fromSquare: from,
                toSquare: to,
                isBackward: true,
                capturedPiece: capPiece,
                capturedSquare: capPiece != nil ? from : nil,
                rookPiece: nil,
                rookFromSquare: nil,
                rookToSquare: nil
            )
        }
    }
}

private struct BoardMoveAnimationData: Equatable {
    let piece: PieceClass
    let fromSquare: ChessSquare
    let toSquare: ChessSquare
    let fromPoint: CGPoint
    let toPoint: CGPoint
    let capturedPiece: PieceClass?
    let capturedPoint: CGPoint?
    let capturedSquare: ChessSquare?
    let isBackward: Bool
    let rookPiece: PieceClass?
    let rookFromPoint: CGPoint?
    let rookToPoint: CGPoint?
    let rookToSquare: ChessSquare?
    let style: MoveAnimationStyle
}

@MainActor
private struct FlyingPieceOverlay: View, Animatable {
    var progress: CGFloat
    let fromPoint: CGPoint
    let toPoint: CGPoint
    let piece: PieceClass
    let size: CGFloat
    let style: MoveAnimationStyle

    nonisolated var animatableData: CGFloat {
        get { MainActor.assumeIsolated { progress } }
        set { MainActor.assumeIsolated { progress = newValue } }
    }

    var body: some View {
        let x = fromPoint.x + (toPoint.x - fromPoint.x) * progress
        let y = fromPoint.y + (toPoint.y - fromPoint.y) * progress

        let arcLift: CGFloat = {
            if style == .jump {
                return -sin(progress * .pi) * max(14, size * 0.40)
            }
            return 0
        }()

        let scale: CGFloat = {
            if style == .jump {
                return 1.0 + sin(progress * .pi) * 0.15
            } else if style == .smooth {
                return 1.0 + sin(progress * .pi) * 0.05
            }
            return 1.0
        }()

        let shadowRadius: CGFloat = {
            if style == .jump {
                return 3 + sin(progress * .pi) * 7
            } else if style == .smooth {
                return 2 + sin(progress * .pi) * 4
            }
            return 2
        }()

        let shadowY: CGFloat = {
            if style == .jump {
                return 2 + sin(progress * .pi) * 5
            } else if style == .smooth {
                return 1 + sin(progress * .pi) * 2
            }
            return 1
        }()

        PieceView(piece: piece, size: size)
            .scaleEffect(scale)
            .shadow(color: .black.opacity(0.32), radius: shadowRadius, y: shadowY)
            .position(x: x, y: y + arcLift)
            .allowsHitTesting(false)
    }
}

@MainActor
private struct DissolvingCapturedPiece: View, Animatable {
    var progress: CGFloat
    let point: CGPoint
    let piece: PieceClass
    let size: CGFloat
    var isAppearing: Bool = false

    nonisolated var animatableData: CGFloat {
        get { MainActor.assumeIsolated { progress } }
        set { MainActor.assumeIsolated { progress = newValue } }
    }

    var body: some View {
        let opacity: Double = isAppearing
            ? min(1.0, max(0.0, Double(progress) * 1.6))
            : max(0.0, 1.0 - Double(progress) * 1.6)

        let scale: CGFloat = isAppearing
            ? min(1.0, max(0.70, 0.70 + progress * 0.30))
            : max(0.01, 1.0 - progress * 0.20)

        PieceView(piece: piece, size: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(point)
            .allowsHitTesting(false)
    }
}

