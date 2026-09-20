import ChessKit
import SwiftUI

struct EditMoveSheet: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var from: ChessSquare?
    @State private var to: ChessSquare?
    @State private var promotion: Piece.Kind = .queen
    @State private var needsPromotion = false
    @State private var error: String?

    private var boardFEN: String {
        if let ply = model.editTargetPly, let fen = model.engine.fenBeforePly(ply) {
            return fen
        }
        if model.editReplacesLast, let previous = model.engine.fenBeforeLastMove() {
            return previous
        }
        return model.engine.fen
    }

    private var navigationTitle: String {
        if let ply = model.editTargetPly {
            return "Edit move \(ply + 1)"
        }
        return "Edit move"
    }

    private var trialEngine: GameEngine? {
        try? GameEngine(fen: boardFEN)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Tap from, then to")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)

                        DigitalBoardView(
                            fen: boardFEN,
                            selected: from,
                            interactive: true,
                            onTap: handleTap
                        )
                        .frame(maxHeight: 360)

                        if needsPromotion {
                            promotionPicker
                        }

                        if !model.ambiguousMoves.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Legal matches")
                                    .font(.callout)
                                    .foregroundStyle(Theme.textSecondary)
                                ForEach(model.ambiguousMoves, id: \.san) { move in
                                    Button(move.san) {
                                        model.applyEdit(san: move.san)
                                    }
                                    .font(.body.monospaced())
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                        }

                        if let error {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(Theme.danger)
                        }

                        PrimaryButton(title: "Apply", isDisabled: from == nil || to == nil) {
                            applyFromTo()
                        }
                        SecondaryButton(title: "Undo last", isDisabled: model.engine.plyCount == 0) {
                            model.undoLast()
                            dismiss()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private var promotionPicker: some View {
        HStack(spacing: 12) {
            ForEach([Piece.Kind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                Button {
                    promotion = kind
                } label: {
                    Text(label(for: kind))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            promotion == kind ? Theme.accent : Theme.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(promotion == kind ? Theme.onAccent : Theme.textPrimary)
                }
                .accessibilityLabel(label(for: kind))
            }
        }
    }

    private func handleTap(_ square: ChessSquare) {
        error = nil
        if from == nil {
            from = square
            return
        }
        if to == nil {
            to = square
            needsPromotion = isPromotion(from: from!, to: square)
            return
        }
        from = square
        to = nil
        needsPromotion = false
    }

    private func isPromotion(from: ChessSquare, to: ChessSquare) -> Bool {
        guard let engine = trialEngine else { return false }
        let pieces = FenCodec.parsePieces(engine.fen)
        guard let piece = pieces[from], piece == .whitePawn || piece == .blackPawn else { return false }
        return to.rank == 0 || to.rank == 7
    }

    private func applyFromTo() {
        guard let from, let to, let engine = trialEngine else { return }
        let matches = engine.legalMoves().filter { move in
            ChessSquare.parse(move.start.notation) == from
                && ChessSquare.parse(move.end.notation) == to
        }
        if matches.isEmpty {
            error = "That move isn’t legal from the last good position."
            return
        }
        let chosen: Move
        if matches.count == 1 {
            chosen = matches[0]
        } else if needsPromotion {
            if let promo = matches.first(where: { $0.promotedPiece?.kind == promotion }) {
                chosen = promo
            } else {
                error = "Pick a promotion piece."
                return
            }
        } else {
            error = "More than one legal move. Pick from the list."
            model.ambiguousMoves = matches
            return
        }
        model.applyEdit(san: chosen.san)
    }

    private func label(for kind: Piece.Kind) -> String {
        switch kind {
        case .queen: "Q"
        case .rook: "R"
        case .bishop: "B"
        case .knight: "N"
        default: "?"
        }
    }
}
