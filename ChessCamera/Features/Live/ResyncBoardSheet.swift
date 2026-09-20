import ChessKit
import SwiftUI

/// Mid-game mismatch UI: trust the digital board (default) or edit/adopt vision.
struct ResyncBoardSheet: View {
    @Bindable var model: RecordingSessionViewModel
    @State private var isEditing = false
    @State private var selectedSquare: ChessSquare?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    mismatchList
                    if isEditing {
                        editSection
                    }
                    actions
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Resync board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancelResync()
                    }
                }
            }
            .alert(
                "Clear move history?",
                isPresented: $model.confirmAdoptVision
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Adopt position", role: .destructive) {
                    Task { await model.applyResync(trustVision: true) }
                }
            } message: {
                Text("Loading this board position will remove all recorded moves and start fresh from here.")
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera and digital board disagree.")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Trust digital keeps your move list and re-baselines vision. Adopting the camera position clears history.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var mismatchList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mismatchTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.caution)
            if model.resyncMismatchSquares.isEmpty {
                Text("Occupancy matches, but piece identities differ—or edits resolved the gaps.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(model.resyncMismatchSquares.map(\.algebraic).joined(separator: ", "))
                    .font(.body.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var mismatchTitle: String {
        let count = model.resyncMismatchSquares.count
        if count == 0 { return "No square deltas" }
        return count == 1 ? "1 square differs" : "\(count) squares differ"
    }

    private var editSection: some View {
        VStack(spacing: 12) {
            DigitalBoardView(
                fen: model.proposedFEN,
                orientation: .whiteAtBottom,
                selected: selectedSquare,
                interactive: true,
                onTap: { square in
                    if selectedSquare == square {
                        selectedSquare = nil
                    } else {
                        selectedSquare = square
                    }
                }
            )
            .frame(maxHeight: 280)

            if let square = selectedSquare {
                inlinePalette(for: square)
            } else {
                Text("Tap a square to correct its piece")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Trust digital") {
                Task { await model.applyResync(trustVision: false) }
            }

            if !isEditing {
                SecondaryButton(title: "Edit position") {
                    isEditing = true
                    model.refreshResyncProposal()
                }
            } else {
                if model.resyncOccupancyMatchesEngine && model.visionPlacementMatchesEngine {
                    SecondaryButton(title: "Matches digital — re-baseline") {
                        Task { await model.applyResync(trustVision: false) }
                    }
                }

                PrimaryButton(
                    title: adoptButtonTitle,
                    isDisabled: !model.isLegalProposedFEN
                ) {
                    if model.engine.plyCount > 0 {
                        model.confirmAdoptVision = true
                    } else {
                        Task { await model.applyResync(trustVision: true) }
                    }
                }
            }
        }
    }

    private var adoptButtonTitle: String {
        model.engine.plyCount > 0 ? "Adopt position (clears history)" : "Adopt position"
    }

    private func inlinePalette(for square: ChessSquare) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Selected: \(square.algebraic.uppercased())")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("Done") { selectedSquare = nil }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 6) {
                paletteButton("♔", .whiteKing, square)
                paletteButton("♕", .whiteQueen, square)
                paletteButton("♖", .whiteRook, square)
                paletteButton("♗", .whiteBishop, square)
                paletteButton("♘", .whiteKnight, square)
                paletteButton("♙", .whitePawn, square)
            }
            HStack(spacing: 6) {
                paletteButton("♚", .blackKing, square)
                paletteButton("♛", .blackQueen, square)
                paletteButton("♜", .blackRook, square)
                paletteButton("♝", .blackBishop, square)
                paletteButton("♞", .blackKnight, square)
                paletteButton("♟", .blackPawn, square)
                Button {
                    model.setPiece(.empty, at: square)
                    model.refreshResyncProposal()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.statusRed)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func paletteButton(_ symbol: String, _ piece: PieceClass, _ square: ChessSquare) -> some View {
        let isSelected = model.classifiedClasses[square] == piece
        return Button {
            model.setPiece(piece, at: square)
            model.refreshResyncProposal()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(symbol)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    isSelected ? Theme.accent.opacity(0.18) : Theme.background,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: 1)
                }
        }
    }
}
