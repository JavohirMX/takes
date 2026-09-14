import SwiftUI

struct ConfirmStartView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
    }

    private var portrait: some View {
        ScrollView {
            VStack(spacing: 24) {
                warpedBoard
                    .frame(maxHeight: 180)
                digitalBoard
                    .frame(maxHeight: 320)
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
            exportCropsButton
        }
        .padding(16)
    }

    private var portraitCTA: some View {
        VStack(spacing: 8) {
            startButton
            exportCropsButton
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
            onTap: { model.cyclePiece(at: $0) }
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
        } else if model.isStandardStart {
            Label("Standard starting position.", systemImage: "checkmark.circle")
                .font(.body)
                .foregroundStyle(Theme.accent)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("This doesn’t look like the start.", systemImage: "exclamationmark.triangle")
                    .font(.body)
                    .foregroundStyle(Theme.caution)
                if model.classifierAvailable {
                    SecondaryButton(title: "Recapture") {
                        Task { await model.recapture() }
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

    private var exportCropsButton: some View {
        Button("Export 64 crops") {
            model.exportCrops()
        }
        .font(.callout)
        .foregroundStyle(Theme.textSecondary)
        .frame(minHeight: 44)
        .accessibilityLabel("Export 64 crops")
    }
}
