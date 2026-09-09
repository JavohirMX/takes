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
    private var appliedSANs: [String] = []

    var fen: String { board.position.fen }
    var pgn: String { game.pgn }
    var state: Board.State { board.state }

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

    func occupancy() -> Occupancy {
        Self.occupancy(of: board)
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

    private func rebuildFromAppliedMoves() throws {
        let start = game.startingPosition ?? .standard
        board = Board(position: start)
        game = Game(startingWith: start)
        currentIndex = game.startingIndex
        let sans = appliedSANs
        appliedSANs = []
        for san in sans {
            try apply(san: san)
        }
    }
}
