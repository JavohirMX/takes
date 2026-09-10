import ChessKit
import SwiftUI
import UIKit

struct LiveRecordingView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                landscape
            } else {
                portrait
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom) {
            if verticalSizeClass != .compact {
                hud
            }
        }
        .confirmationDialog(
            "End game and save PGN?",
            isPresented: $model.confirmEndGame,
            titleVisibility: .visible
        ) {
            Button("End", role: .destructive, action: model.confirmEndAndSave)
            Button("Keep playing", role: .cancel) { model.confirmEndGame = false }
        }
        .sheet(isPresented: $model.showEditSheet) {
            EditMoveSheet(model: model)
        }
        .sheet(isPresented: $model.showShareSheet) {
            ShareSheet(items: model.shareItems)
        }
    }

    private var portrait: some View {
        VStack(spacing: 0) {
            cameraBlock
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            DigitalBoardView(
                fen: model.engine.fen,
                orientation: model.orientation,
                lastMove: model.engine.lastMoveSquares
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity)
        }
    }

    private var landscape: some View {
        HStack(spacing: 0) {
            cameraBlock
            VStack(spacing: 12) {
                DigitalBoardView(
                    fen: model.engine.fen,
                    orientation: model.orientation,
                    lastMove: model.engine.lastMoveSquares
                )
                MoveListView(sans: model.engine.appliedSANs)
                FenBar(fen: model.engine.fen, copyAction: model.copyFEN)
                hudControls
            }
            .padding(16)
            .frame(maxWidth: 360)
            .background(Theme.background)
        }
    }

    private var cameraBlock: some View {
        ZStack {
            CameraPreview(
                session: model.liveCaptureSession,
                stillImage: model.previewImage,
                videoRotationAngle: model.previewRotationAngle
            )
            BoardQuadOverlay(
                quad: model.quad,
                bufferSize: model.bufferSize,
                style: model.trackingLost ? .poor : .locked,
                pulse: false
            )
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        if let thumb = model.warpedThumbnail {
                            Image(uiImage: UIImage(cgImage: thumb))
                                .resizable()
                                .scaledToFit()
                        }
                        OccupancyGridOverlay(
                            occupancy: model.liveOccupancy,
                            orientation: model.orientation
                        )
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                    .padding(12)
                }
                Spacer()
            }
        }
    }

    private var hud: some View {
        VStack(spacing: 12) {
            StatusBanner(
                kind: statusKind,
                showFix: model.phase == .awaitingEdit,
                onFix: { model.beginEdit(replacingLast: false) }
            )
            FenBar(fen: model.engine.fen, copyAction: model.copyFEN)
            hudControls
        }
        .padding(16)
        .background(UIAccessibility.isReduceTransparencyEnabled ? Theme.surface : Theme.overlayScrim)
    }

    private var hudControls: some View {
        HStack(spacing: 12) {
            Button {
                model.requestEndGame()
            } label: {
                Text("End")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("End game")

            Button {
                model.undoLast()
            } label: {
                Text("Undo")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(!model.canUndo)
            .accessibilityLabel("Undo last move")

            Menu {
                Button("Adjust corners") { model.adjustCorners() }
                Button("Fix last move") { model.beginEdit(replacingLast: true) }
                    .disabled(model.engine.plyCount == 0)
                Button("Export 64 crops") { model.exportCrops() }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More actions")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var statusKind: StatusKind {
        if model.trackingLost { return .trackingLost }
        switch model.phase {
        case .disturbed:
            return .disturbed
        case .awaitingEdit:
            return .awaitingEdit
        case .recording:
            if case .check = model.engine.state {
                return .check(model.lastSAN ?? model.engine.formattedLastSAN ?? "")
            }
            return .recording(model.lastSAN ?? model.engine.formattedLastSAN ?? "Recording")
        default:
            return .recording(model.lastSAN ?? "Recording")
        }
    }
}

#Preview("recording") {
    LiveRecordingView(model: RecordingSessionViewModel())
}

#Preview("disturbed") {
    let model = RecordingSessionViewModel()
    model.phase = .disturbed
    return LiveRecordingView(model: model)
}

#Preview("awaitingEdit") {
    let model = RecordingSessionViewModel()
    model.phase = .awaitingEdit
    return LiveRecordingView(model: model)
}
