import ChessKit
import Foundation

enum PieceClass: String, CaseIterable, Sendable {
    case empty
    case whitePawn, whiteKnight, whiteBishop, whiteRook, whiteQueen, whiteKing
    case blackPawn, blackKnight, blackBishop, blackRook, blackQueen, blackKing

    var pieceColor: Piece.Color? {
        switch self {
        case .whitePawn, .whiteKnight, .whiteBishop, .whiteRook, .whiteQueen, .whiteKing:
            return .white
        case .blackPawn, .blackKnight, .blackBishop, .blackRook, .blackQueen, .blackKing:
            return .black
        case .empty:
            return nil
        }
    }
}
