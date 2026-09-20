import ChessKit
import SwiftUI

struct ConfirmStartView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var selectedSquare: ChessSquare?

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isLandscape {
                landscape
            } else {
                portrait
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(nil, value: verticalSizeClass)
        .navigationTitle(model.isContinuingGame ? "Continue game" : "Confirm start")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom) {
            if !isLandscape {
                portraitCTA
            }
        }
        .sheet(isPresented: $model.showShareSheet) {
            ShareSheet(items: model.shareItems)
        }
        .sheet(item: $selectedSquare) { square in
            PiecePickerPopover(
                square: square,
                currentPiece: model.classifiedClasses[square] ?? .empty,
                onSelect: { piece in
                    model.setPiece(piece, at: square)
                },
                onDismiss: {
                    selectedSquare = nil
                }
            )
        }
    }

    private var portrait: some View {
        ScrollView {
            VStack(spacing: 20) {
                warpedBoard
                    .frame(maxHeight: 180)
                digitalBoard
                    .frame(maxHeight: 320)
                inlinePalette
                Text(selectedSquare == nil ? "Tap any square to correct its piece" : "Select a piece from the palette above")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if !model.isStandardStart && !model.isContinuingGame {
                    sideToMoveRow
                }
                if !model.isVideoImport {
                    clockPresetRow
                }
                rotateRow
                statusBlock
            }
            .padding(16)
        }
    }

    private var landscape: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                digitalBoard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                inlinePalette
            }
            .padding(16)
            landscapeSidebar
                .frame(width: 320)
                .background(Theme.background)
        }
    }

    private var landscapeSidebar: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 16) {
                    warpedBoard
                        .frame(maxWidth: 140, maxHeight: 140)
                        .frame(maxWidth: .infinity)
                    if !model.isStandardStart && !model.isContinuingGame {
                        sideToMoveRow
                    }
                    if !model.isVideoImport {
                        clockPresetRow
                    }
                    rotateRow
                    statusBlock
                }
            }
            startButton
        }
        .padding(16)
    }

    private var portraitCTA: some View {
        VStack(spacing: 8) {
            startButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }

    private var digitalBoard: some View {
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
    }

    @ViewBuilder
    private var warpedBoard: some View {
        if model.warpedThumbnail != nil {
            WarpedBoardView(
                image: model.warpedThumbnail,
                orientation: model.orientation,
                grid: model.refinedGrid
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            }
        }
    }

    private var rotateRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "rotate.right")
                .foregroundStyle(Theme.accent)
            Text("Rotate until White is at the bottom.")
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Button("Rotate") {
                Task { await model.rotateBoard() }
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityLabel("Rotate board")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var statusBlock: some View {
        if model.isClassifying {
            HStack(spacing: 12) {
                ProgressView()
                Text("Reading pieces…")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if model.gridSnapFailed {
                    Label(
                        "Couldn’t snap to squares—drag corners or Rescan.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout)
                    .foregroundStyle(Theme.caution)
                }
                if model.isContinuingGame {
                    Label(
                        "Continuing with \(model.committedPlyCount) move\(model.committedPlyCount == 1 ? "" : "s") — Start keeps your history.",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                } else if model.isStandardStart {
                    Label("Standard starting position.", systemImage: "checkmark.circle")
                        .font(.body)
                        .foregroundStyle(Theme.accent)
                } else {
                    Label("This doesn’t look like the start.", systemImage: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(Theme.caution)
                    if model.pieceDetectionAvailable {
                        HStack(spacing: 10) {
                            SecondaryButton(title: "Recapture") {
                                Task { await model.recapture() }
                            }
                            SecondaryButton(title: "Reset to standard") {
                                model.useStandardStartingPosition()
                            }
                        }
                    } else {
                        SecondaryButton(title: "Reset to standard") {
                            model.useStandardStartingPosition()
                        }
                    }
                    if model.isLegalProposedFEN {
                        Button("Start Game from Here") {
                            model.startRecording(mode: .newGame)
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private var sideToMoveRow: some View {
        HStack(spacing: 12) {
            Text("Side to move")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Picker("Side to move", selection: Binding(
                get: { model.sideToMove },
                set: { model.setSideToMove($0) }
            )) {
                Text("White").tag(Piece.Color.white)
                Text("Black").tag(Piece.Color.black)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var clockPresetRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.accent)
                Text("Clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let label = GameClockSettings.timeControlString(for: model.sessionClockPreset) {
                    Text(label)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Picker("Clock", selection: $model.sessionClockPreset) {
                ForEach(ClockPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Clock preset")
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var inlinePalette: some View {
        if let square = selectedSquare {
            VStack(spacing: 8) {
                HStack {
                    Text("Selected: \(square.algebraic.uppercased())")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Button("Done") {
                        selectedSquare = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                }

                // White pieces
                HStack(spacing: 6) {
                    paletteButton(symbol: "♔", piece: .whiteKing, square: square)
                    paletteButton(symbol: "♕", piece: .whiteQueen, square: square)
                    paletteButton(symbol: "♖", piece: .whiteRook, square: square)
                    paletteButton(symbol: "♗", piece: .whiteBishop, square: square)
                    paletteButton(symbol: "♘", piece: .whiteKnight, square: square)
                    paletteButton(symbol: "♙", piece: .whitePawn, square: square)
                }

                // Black pieces & Clear
                HStack(spacing: 6) {
                    paletteButton(symbol: "♚", piece: .blackKing, square: square)
                    paletteButton(symbol: "♛", piece: .blackQueen, square: square)
                    paletteButton(symbol: "♜", piece: .blackRook, square: square)
                    paletteButton(symbol: "♝", piece: .blackBishop, square: square)
                    paletteButton(symbol: "♞", piece: .blackKnight, square: square)
                    paletteButton(symbol: "♟", piece: .blackPawn, square: square)
                    Button {
                        model.setPiece(.empty, at: square)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.statusRed)
                            .frame(width: 36, height: 36)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.statusRed.opacity(0.4), lineWidth: 1)
                            }
                    }
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
            }
        }
    }

    private func paletteButton(symbol: String, piece: PieceClass, square: ChessSquare) -> some View {
        let isSelected = model.classifiedClasses[square] == piece
        return Button {
            model.setPiece(piece, at: square)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(symbol)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(isSelected ? Theme.accent.opacity(0.18) : Theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if model.isContinuingGame {
            PrimaryButton(title: "Continue recording") {
                model.startRecording(mode: .continueOrResync)
            }
        } else if !model.pieceDetectionAvailable {
            PrimaryButton(title: "Use standard starting position") {
                model.useStandardStartingPosition()
                model.startRecording(mode: .newGame)
            }
        } else {
            let title = model.isStandardStart ? "Start recording" : "Start Game from Here"
            PrimaryButton(
                title: title,
                isDisabled: !model.isLegalProposedFEN || model.isClassifying
            ) {
                model.startRecording(mode: .newGame)
            }
        }
    }
}
