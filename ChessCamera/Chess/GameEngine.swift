import ChessKit
import Foundation
import Observation

enum GameEngineError: Error, Equatable {
    case invalidFEN(String)
    case illegalMove(String)
    case nothingToUndo
}

@Observable
final class GameEngine {
    private(set) var board: Board
    private(set) var game: Game
    private var currentIndex: MoveTree.Index
    private(set) var appliedSANs: [String] = []
    private(set) var lastMove: Move?

    var fen: String { board.position.fen }
    var pgn: String { game.pgn }
    var state: Board.State { board.state }
    var plyCount: Int { appliedSANs.count }
    var lastMoveSquares: (from: ChessSquare, to: ChessSquare)? {
        guard let lastMove else { return nil }
        guard let from = ChessSquare.parse(lastMove.start.notation),
              let to = ChessSquare.parse(lastMove.end.notation) else { return nil }
        return (from, to)
    }

    var isTerminal: Bool {
        switch board.state {
        case .checkmate, .draw: true
        default: false
        }
    }

    var resultTitle: String {
        switch board.state {
        case .checkmate(let color):
            color == .white ? "Checkmate — Black wins" : "Checkmate — White wins"
        case .draw:
            "Draw"
        default:
            "Game ended"
        }
    }

    var resultToken: String {
        switch board.state {
        case .checkmate(let color):
            color == .white ? "0-1" : "1-0"
        case .draw:
            "½-½"
        default:
            "*"
        }
    }

    var formattedLastSAN: String? {
        guard let san = appliedSANs.last else { return nil }
        let plies = appliedSANs.count
        let number = (plies + 1) / 2
        if plies.isMultiple(of: 2) {
            return "\(number)... \(san)"
        }
        return "\(number). \(san)"
    }

    init() {
        let newGame = Game()
        board = Board()
        game = newGame
        currentIndex = newGame.startingIndex
    }

    init(fen: String) throws {
        guard let position = Position(fen: fen) else {
            throw GameEngineError.invalidFEN(fen)
        }
        let newGame = Game(startingWith: position)
        board = Board(position: position)
        game = newGame
        currentIndex = newGame.startingIndex
    }

    func apply(move: Move) throws {
        var trial = board
        guard let executed = trial.move(pieceAt: move.start, to: move.end) else {
            throw GameEngineError.illegalMove(move.san)
        }

        var committed = executed
        if let promoted = move.promotedPiece {
            committed = trial.completePromotion(of: executed, to: promoted.kind)
        } else if case .promotion(let pending) = trial.state {
            committed = trial.completePromotion(of: pending, to: .queen)
        }

        board = trial
        currentIndex = game.make(move: committed, from: currentIndex)
        appliedSANs.append(committed.san)
        lastMove = committed
    }

    func apply(san: String) throws {
        guard let move = Move(san: san, position: board.position) else {
            throw GameEngineError.illegalMove(san)
        }
        try apply(move: move)
    }

    func undo() throws {
        guard !appliedSANs.isEmpty else {
            throw GameEngineError.nothingToUndo
        }
        appliedSANs.removeLast()
        try rebuildFromAppliedMoves()
    }

    func replaceLast(with san: String) throws {
        guard !appliedSANs.isEmpty else {
            throw GameEngineError.nothingToUndo
        }
        appliedSANs.removeLast()
        try rebuildFromAppliedMoves()
        try apply(san: san)
    }

    func fenBeforeLastMove() -> String? {
        guard !appliedSANs.isEmpty else { return nil }
        let sans = Array(appliedSANs.dropLast())
        do {
            let snapshot = try GameEngine(fen: (game.startingPosition ?? .standard).fen)
            for san in sans {
                try snapshot.apply(san: san)
            }
            return snapshot.fen
        } catch {
            return nil
        }
    }

    func legalMoves() -> [Move] {
        var moves: [Move] = []
        for start in Square.allCases {
            for end in board.legalMoves(forPieceAt: start) {
                var trial = board
                guard let executed = trial.move(pieceAt: start, to: end) else { continue }
                if case .promotion = trial.state {
                    for kind in [Piece.Kind.queen, .rook, .bishop, .knight] {
                        var promo = board
                        guard let base = promo.move(pieceAt: start, to: end) else { continue }
                        moves.append(promo.completePromotion(of: base, to: kind))
                    }
                } else {
                    moves.append(executed)
                }
            }
        }
        return moves
    }

    func pieceMap() -> [ChessSquare: PieceClass] {
        FenCodec.parsePieces(fen)
    }

    func occupancy() -> Occupancy {
        Self.occupancy(of: board)
    }

    func resetToStart() {
        let newGame = Game()
        board = Board()
        game = newGame
        currentIndex = newGame.startingIndex
        appliedSANs = []
        lastMove = nil
    }

    func load(fen: String) throws {
        guard let position = Position(fen: fen) else {
            throw GameEngineError.invalidFEN(fen)
        }
        let newGame = Game(startingWith: position)
        board = Board(position: position)
        game = newGame
        currentIndex = newGame.startingIndex
        appliedSANs = []
        lastMove = nil
    }

    static func occupancy(of board: Board) -> Occupancy {
        var occupancy = Occupancy()
        for piece in board.position.pieces {
            let square = ChessSquare(
                file: piece.square.file.number - 1,
                rank: piece.square.rank.value - 1
            )
            occupancy.set(square, occupied: true)
        }
        return occupancy
    }

    /// Squares a legal move or fast opponent reply can fill or empty. Used to gate YOLO occupancy.
    static func occupancyPrior(of board: Board, maxNewClears: Int = 4) -> OccupancyPrior {
        let before = occupancy(of: board)
        var fillable = Occupancy()
        var clearable = Occupancy()

        func accumulate(_ after: Board) {
            let afterOcc = occupancy(of: after)
            clearable.bits |= before.bits & ~afterOcc.bits
            fillable.bits |= afterOcc.bits & ~before.bits
        }

        for afterFirst in legalSuccessorBoards(board) {
            accumulate(afterFirst)
            for afterSecond in legalSuccessorBoards(afterFirst) {
                accumulate(afterSecond)
            }
        }
        return OccupancyPrior(fillable: fillable, clearable: clearable, maxNewClears: maxNewClears)
    }

    /// Queen promotions only: occupancy does not distinguish promo piece.
    private static func legalSuccessorBoards(_ board: Board) -> [Board] {
        var boards: [Board] = []
        let side = board.position.sideToMove
        for start in Square.allCases {
            guard board.position.piece(at: start)?.color == side else { continue }
            for end in board.legalMoves(forPieceAt: start) {
                var trial = board
                guard trial.move(pieceAt: start, to: end) != nil else { continue }
                if case .promotion = trial.state {
                    var promo = board
                    guard let base = promo.move(pieceAt: start, to: end) else { continue }
                    _ = promo.completePromotion(of: base, to: .queen)
                    boards.append(promo)
                } else {
                    boards.append(trial)
                }
            }
        }
        return boards
    }

    private func rebuildFromAppliedMoves() throws {
        let start = game.startingPosition ?? .standard
        board = Board(position: start)
        game = Game(startingWith: start)
        currentIndex = game.startingIndex
        lastMove = nil
        let sans = appliedSANs
        appliedSANs = []
        for san in sans {
            try apply(san: san)
        }
    }
}
