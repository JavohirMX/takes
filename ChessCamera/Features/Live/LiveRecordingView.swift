import ChessKit
import SwiftUI
import UIKit

struct LiveRecordingView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var previewSwap
    @State private var warpIsPrimary = false

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        let layout = isLandscape
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        layout {
            cameraBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(isLandscape ? 0 : 1)
            accessory
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(nil, value: verticalSizeClass)
        .onAppear { warpIsPrimary = false }
        .safeAreaInset(edge: .bottom) {
            if !isLandscape {
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

    @ViewBuilder
    private var accessory: some View {
        if isLandscape {
            landscapeSidebar
        } else {
            VStack(spacing: 0) {
                DigitalBoardView(
                    fen: model.engine.fen,
                    lastMove: model.engine.lastMoveSquares
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxHeight: .infinity)
                RecentPlyStrip(sans: model.committedSANs)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .id(model.committedPlyCount)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var landscapeSidebar: some View {
        VStack(spacing: 12) {
            statusBanner
            DigitalBoardView(
                fen: model.engine.fen,
                lastMove: model.engine.lastMoveSquares
            )
            .frame(maxWidth: 180, maxHeight: 180)
            .frame(maxWidth: .infinity)
            MoveListView(sans: model.committedSANs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            hudControls
        }
        .padding(16)
        .frame(minWidth: 340, maxWidth: 400)
        .frame(maxHeight: .infinity)
        .background(Theme.background)
    }

    private var cameraBlock: some View {
        ZStack {
            cameraFeed(showOverlays: !warpIsPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if warpIsPrimary {
                warpFeed
                    .matchedGeometryEffect(id: "warp", in: previewSwap)
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: togglePreview)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(warpIsPrimary ? "Show camera" : "Show board preview")

            VStack {
                HStack {
                    Spacer()
                    cornerPIP
                }
                Spacer()
            }
        }
    }

    private var cornerPIP: some View {
        Group {
            if warpIsPrimary {
                cameraStill
            } else {
                warpFeed
                    .matchedGeometryEffect(id: "warp", in: previewSwap)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: togglePreview)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(warpIsPrimary ? "Show camera" : "Show board preview")
        .padding(12)
    }

    private func cameraFeed(showOverlays: Bool) -> some View {
        ZStack {
            CameraPreview(
                session: model.liveCaptureSession,
                stillImage: model.previewImage,
                videoRotationAngle: model.previewRotationAngle
            )
            if showOverlays {
                BoardQuadOverlay(
                    quad: model.quad,
                    bufferSize: model.bufferSize,
                    style: model.trackingLost ? .poor : .locked,
                    pulse: false
                )
                if let quad = model.quad {
                    BoardGridOverlay(
                        quad: quad,
                        bufferSize: model.bufferSize,
                        grid: model.refinedGrid
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var cameraStill: some View {
        ZStack {
            if let preview = model.previewImage {
                Image(uiImage: UIImage(cgImage: preview))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Theme.surfaceMuted
            }
        }
        .allowsHitTesting(false)
    }

    private var warpFeed: some View {
        ZStack {
            if let thumb = model.warpedThumbnail {
                Image(uiImage: UIImage(cgImage: thumb))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Theme.surfaceMuted
            }
            OccupancyGridOverlay(
                occupancy: model.liveOccupancy,
                orientation: model.orientation
            )
        }
        .allowsHitTesting(false)
    }

    private func togglePreview() {
        if reduceMotion {
            warpIsPrimary.toggle()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                warpIsPrimary.toggle()
            }
        }
    }

    private var hud: some View {
        VStack(spacing: 12) {
            statusBanner
            hudControls
        }
        .padding(16)
        .background(UIAccessibility.isReduceTransparencyEnabled ? Theme.surface : Theme.overlayScrim)
    }

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBanner(
                kind: statusKind,
                showFix: model.phase == .awaitingEdit,
                onFix: { model.beginEdit(replacingLast: false) },
                showResume: model.phase == .awaitingEdit,
                onResume: { model.resumeRecordingAfterReject() }
            )
            .id("\(model.committedPlyCount)-\(model.lastSAN ?? "")-\(model.phase)")
            if !model.liveDebugLine.isEmpty {
                Text(model.liveDebugLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Capture debug \(model.liveDebugLine)")
            }
        }
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
                    .disabled(model.committedPlyCount == 0)
                Button("Copy FEN") { model.copyFEN() }
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
        if let soft = model.softRejectMessage, model.phase == .recording || model.phase == .disturbed {
            return .softReject(soft)
        }
        switch model.phase {
        case .disturbed:
            return .disturbed(holding: model.lastSAN)
        case .awaitingEdit:
            return .awaitingEdit
        case .recording:
            if case .check = model.engine.state {
                return .check(model.lastSAN ?? "")
            }
            return .recording(model.lastSAN ?? "Recording")
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
