import Testing
@testable import Takes

@Suite
struct BoardAppearanceTests {
    @Test
    func defaultStyleIsTournament() {
        #expect(BoardAppearance.defaultStyle == .tournament)
        #expect(BoardAppearance.styleKey == "boardStyle")
    }

    @Test
    func everyNonEmptyPieceHasAnAssetName() {
        for piece in PieceClass.allCases where piece != .empty {
            #expect(piece.assetName != nil)
        }
        #expect(PieceClass.empty.assetName == nil)
    }

    @Test
    func styleTitlesAreUnique() {
        let titles = BoardStyle.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test
    func moveAnimationStylesHaveValidConfigurations() {
        #expect(MoveAnimationAppearance.defaultStyle == .smooth)
        #expect(MoveAnimationAppearance.key == "moveAnimationStyle")

        for style in MoveAnimationStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(!style.subtitle.isEmpty)
            #expect(!style.icon.isEmpty)
            if style.isSlide {
                #expect(style.animation != nil)
            }
        }

        #expect(MoveAnimationStyle.smooth.isSlide)
        #expect(MoveAnimationStyle.jump.isSlide)
        #expect(MoveAnimationStyle.fast.isSlide)
        #expect(!MoveAnimationStyle.pulse.isSlide)
        #expect(!MoveAnimationStyle.none.isSlide)
        #expect(MoveAnimationStyle.pulse.animation != nil)
        #expect(MoveAnimationStyle.none.animation == nil)
    }

    @Test
    func forwardMoveTransitionDetectedCorrectly() {
        let startFEN = FenCodec.standard
        let e4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let prev = FenCodec.parsePieces(startFEN)
        let curr = FenCodec.parsePieces(e4FEN)
        let e2 = ChessSquare(algebraic: "e2")!
        let e4 = ChessSquare(algebraic: "e4")!

        let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prev,
            curr: curr,
            oldFEN: startFEN,
            currFEN: e4FEN,
            hintLastMove: (from: e2, to: e4)
        )

        #expect(transition != nil)
        #expect(transition?.fromSquare == e2)
        #expect(transition?.toSquare == e4)
        #expect(transition?.movingPiece == .whitePawn)
        #expect(transition?.isBackward == false)
        #expect(transition?.capturedPiece == nil)
    }

    @Test
    func backwardMoveTransitionDetectedCorrectly() {
        let startFEN = FenCodec.standard
        let e4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let prev = FenCodec.parsePieces(e4FEN)
        let curr = FenCodec.parsePieces(startFEN)
        let e2 = ChessSquare(algebraic: "e2")!
        let e4 = ChessSquare(algebraic: "e4")!

        // When moving backward to start, hintLastMove is nil
        let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prev,
            curr: curr,
            oldFEN: e4FEN,
            currFEN: startFEN,
            hintLastMove: nil
        )

        #expect(transition != nil)
        #expect(transition?.fromSquare == e4)
        #expect(transition?.toSquare == e2)
        #expect(transition?.movingPiece == .whitePawn)
        #expect(transition?.isBackward == true)
        #expect(transition?.capturedPiece == nil)
    }

    @Test
    func backwardCastlingTransitionDetectedCorrectly() {
        let beforeCastle = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5"
        let afterCastle = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 b kq - 2 5"
        let prev = FenCodec.parsePieces(afterCastle)
        let curr = FenCodec.parsePieces(beforeCastle)
        let e1 = ChessSquare(algebraic: "e1")!
        let g1 = ChessSquare(algebraic: "g1")!
        let f1 = ChessSquare(algebraic: "f1")!
        let h1 = ChessSquare(algebraic: "h1")!

        let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prev,
            curr: curr,
            oldFEN: afterCastle,
            currFEN: beforeCastle,
            hintLastMove: nil
        )

        #expect(transition != nil)
        #expect(transition?.fromSquare == g1)
        #expect(transition?.toSquare == e1)
        #expect(transition?.movingPiece == .whiteKing)
        #expect(transition?.rookPiece == .whiteRook)
        #expect(transition?.rookFromSquare == f1)
        #expect(transition?.rookToSquare == h1)
        #expect(transition?.isBackward == true)
    }

    @Test
    func multiPlyJumpDoesNotAnimate() {
        let startFEN = FenCodec.standard
        let move5FEN = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 b kq - 2 5"
        let prev = FenCodec.parsePieces(startFEN)
        let curr = FenCodec.parsePieces(move5FEN)

        let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prev,
            curr: curr,
            oldFEN: startFEN,
            currFEN: move5FEN,
            hintLastMove: nil
        )

        #expect(transition == nil)
    }

    @Test
    func backwardCaptureTransitionDetectedCorrectly() {
        let beforeCapture = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
        let afterCapture = "rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2"
        let prev = FenCodec.parsePieces(afterCapture)
        let curr = FenCodec.parsePieces(beforeCapture)
        let d5 = ChessSquare(algebraic: "d5")!
        let e4 = ChessSquare(algebraic: "e4")!

        let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prev,
            curr: curr,
            oldFEN: afterCapture,
            currFEN: beforeCapture,
            hintLastMove: nil
        )

        #expect(transition != nil)
        #expect(transition?.fromSquare == d5)
        #expect(transition?.toSquare == e4)
        #expect(transition?.movingPiece == .whitePawn)
        #expect(transition?.isBackward == true)
        #expect(transition?.capturedPiece == .blackPawn)
        #expect(transition?.capturedSquare == d5)
    }

    @Test
    func backwardEnPassantTransitionDetectedCorrectly() {
        let beforeEP = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3"
        let afterEP = "rnbqkbnr/ppp1pppp/3P4/8/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 3"
        let prev = FenCodec.parsePieces(afterEP)
        let curr = FenCodec.parsePieces(beforeEP)
        let d6 = ChessSquare(algebraic: "d6")!
        let e5 = ChessSquare(algebraic: "e5")!
        let d5 = ChessSquare(algebraic: "d5")!

        let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prev,
            curr: curr,
            oldFEN: afterEP,
            currFEN: beforeEP,
            hintLastMove: nil
        )

        #expect(transition != nil)
        #expect(transition?.fromSquare == d6)
        #expect(transition?.toSquare == e5)
        #expect(transition?.movingPiece == .whitePawn)
        #expect(transition?.isBackward == true)
        #expect(transition?.capturedPiece == .blackPawn)
        #expect(transition?.capturedSquare == d5)
    }

    @Test
    func backwardPromotionTransitionDetectedCorrectly() {
        let beforePromo = "8/4P3/8/8/8/8/8/4K2k w - - 0 1"
        let afterPromo = "4Q3/8/8/8/8/8/8/4K2k b - - 0 1"
        let prev = FenCodec.parsePieces(afterPromo)
        let curr = FenCodec.parsePieces(beforePromo)
        let e8 = ChessSquare(algebraic: "e8")!
        let e7 = ChessSquare(algebraic: "e7")!

        let transition = BoardMoveTransitionDetector.detectTransition(
            prev: prev,
            curr: curr,
            oldFEN: afterPromo,
            currFEN: beforePromo,
            hintLastMove: nil
        )

        #expect(transition != nil)
        #expect(transition?.fromSquare == e8)
        #expect(transition?.toSquare == e7)
        #expect(transition?.movingPiece == .whitePawn)
        #expect(transition?.isBackward == true)
        #expect(transition?.capturedPiece == nil)
    }
}
