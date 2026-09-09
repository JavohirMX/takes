import Foundation

enum PieceClass: String, CaseIterable, Sendable {
    case empty
    case whitePawn, whiteKnight, whiteBishop, whiteRook, whiteQueen, whiteKing
    case blackPawn, blackKnight, blackBishop, blackRook, blackQueen, blackKing
}
