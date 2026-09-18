import ChessKit
import SwiftUI

/// Popover / sheet allowing 1-tap piece selection for a specific square,
/// replacing the slow 13-tap sequential cycling.
struct PiecePickerPopover: View {
    let square: ChessSquare
    let currentPiece: PieceClass
    let onSelect: (PieceClass) -> Void
    let onDismiss: () -> Void

    @State private var selectedColor: Piece.Color = .white

    init(
        square: ChessSquare,
        currentPiece: PieceClass,
        onSelect: @escaping (PieceClass) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.square = square
        self.currentPiece = currentPiece
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        _selectedColor = State(initialValue: currentPiece.pieceColor ?? (square.rank < 4 ? .white : .black))
    }

    private var pieceKinds: [(String, PieceClass, PieceClass)] {
        [
            ("King", .whiteKing, .blackKing),
            ("Queen", .whiteQueen, .blackQueen),
            ("Rook", .whiteRook, .blackRook),
            ("Bishop", .whiteBishop, .blackBishop),
            ("Knight", .whiteKnight, .blackKnight),
            ("Pawn", .whitePawn, .blackPawn)
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Square \(square.algebraic.uppercased())")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Picker("Color", selection: $selectedColor) {
                Text("White").tag(Piece.Color.white)
                Text("Black").tag(Piece.Color.black)
            }
            .pickerStyle(.segmented)

            // Piece grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(pieceKinds, id: \.0) { title, whiteP, blackP in
                    let target = selectedColor == .white ? whiteP : blackP
                    let isSelected = currentPiece == target
                    Button {
                        onSelect(target)
                        onDismiss()
                    } label: {
                        VStack(spacing: 6) {
                            PieceView(piece: target, size: 36)
                            Text(title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            isSelected ? Theme.accent.opacity(0.18) : Theme.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? Theme.accent : Theme.border.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Clear button
            Button {
                onSelect(.empty)
                onDismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                    Text("Empty square")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(currentPiece == .empty ? Theme.caution : Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Theme.surface)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }
}
