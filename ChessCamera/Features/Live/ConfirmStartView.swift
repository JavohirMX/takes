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
        .navigationTitle("Confirm start")
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
                Text("Tap any square to correct its piece")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                rotateRow
                statusBlock
            }
            .padding(16)
        }
    }

    private var landscape: some View {
        HStack(spacing: 0) {
            digitalBoard
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            landscapeSidebar
                .frame(width: 300)
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
            interactive: true,
            onTap: { selectedSquare = $0 }
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
                if model.isStandardStart {
                    Label("Standard starting position.", systemImage: "checkmark.circle")
                        .font(.body)
                        .foregroundStyle(Theme.accent)
                } else {
                    Label("This doesn’t look like the start.", systemImage: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(Theme.caution)
                    if model.classifierAvailable {
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
                        Button("Continue anyway") {
                            model.startRecording()
                        }
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if !model.classifierAvailable {
            PrimaryButton(title: "Use standard starting position") {
                model.useStandardStartingPosition()
                model.startRecording()
            }
        } else {
            PrimaryButton(
                title: "Start recording",
                isDisabled: !model.isLegalProposedFEN || model.isClassifying
            ) {
                model.startRecording()
            }
        }
    }
}
