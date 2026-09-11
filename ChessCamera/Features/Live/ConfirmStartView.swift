import SwiftUI

struct ConfirmStartView: View {
    @Bindable var model: RecordingSessionViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    if model.warpedThumbnail != nil {
                        WarpedBoardView(
                            image: model.warpedThumbnail,
                            orientation: model.orientation,
                            grid: model.refinedGrid
                        )
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        }
                    }

                    DigitalBoardView(
                        fen: model.proposedFEN,
                        orientation: model.orientation,
                        interactive: true,
                        onTap: { model.cyclePiece(at: $0) }
                    )
                    .frame(maxHeight: 320)

                    HStack(spacing: 12) {
                        Image(systemName: "rotate.right")
                            .foregroundStyle(Theme.accent)
                        Text("Rotate until the files match the camera")
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button("Rotate") {
                            Task { await model.rotateBoard() }
                        }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityLabel("Rotate board")
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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

                    Button("Export 64 crops") {
                        model.exportCrops()
                    }
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Export 64 crops")
                }
                .padding(16)
            }
        }
        .navigationTitle("Confirm start")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showShareSheet) {
            ShareSheet(items: model.shareItems)
        }
    }
}
