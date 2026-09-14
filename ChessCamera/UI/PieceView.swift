import SwiftUI
import UIKit

struct PieceView: View {
    var piece: PieceClass
    var size: CGFloat

    var body: some View {
        if piece != .empty {
            if let name = piece.assetName, UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            } else if !piece.glyph.isEmpty {
                Text(piece.glyph)
                    .font(.system(size: size * 0.82))
                    .foregroundStyle(piece.isWhite ? Color.white : Color.black)
                    .shadow(color: piece.isWhite ? .black.opacity(0.35) : .clear, radius: 0.5)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension PieceClass {
    var assetName: String? {
        switch self {
        case .empty: nil
        case .whiteKing: "wK"
        case .whiteQueen: "wQ"
        case .whiteRook: "wR"
        case .whiteBishop: "wB"
        case .whiteKnight: "wN"
        case .whitePawn: "wP"
        case .blackKing: "bK"
        case .blackQueen: "bQ"
        case .blackRook: "bR"
        case .blackBishop: "bB"
        case .blackKnight: "bN"
        case .blackPawn: "bP"
        }
    }
}
