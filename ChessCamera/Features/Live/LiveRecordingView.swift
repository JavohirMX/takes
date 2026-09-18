import ChessKit
import SwiftUI
import UIKit

struct LiveRecordingView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var previewSwap
    @State private var warpIsPrimary = false
    @AppStorage(SpeechSettings.key) private var speakMoves = false
    @AppStorage(DebugOverlaySettings.showYoloDotsKey) private var showYoloDots = true
    @AppStorage(DebugOverlaySettings.showCaptureDiagnosticsKey) private var showCaptureDiagnostics = true
    @AppStorage(DebugOverlaySettings.showBoardGridKey) private var showBoardGrid = true
    @AppStorage(DebugOverlaySettings.showOccupancyOverlayKey) private var showOccupancyOverlay = true
    @AppStorage(DebugOverlaySettings.showPieceBoxesKey) private var showPieceBoxes = false
    @AppStorage(AnalysisSettings.liveHintsKey) private var liveHints = false
    @AppStorage(AnalysisSettings.liveShowEvalKey) private var liveShowEval = true
    @AppStorage(AnalysisSettings.liveShowArrowKey) private var liveShowArrow = true

    @State private var showEndResolution = false
    @State private var showScoreSheet = false
    @State private var matchModeActive = false
    @State private var focusPoint: CGPoint?
    @State private var showFocusReticle = false

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var liveBestArrow: BoardArrow? {
        guard liveHints, liveShowArrow else { return nil }
        guard model.phase == .recording || model.phase == .disturbed || model.phase == .awaitingEdit || model.phase == .gameOver else { return nil }
        return model.liveAnalysis?.bestArrow
    }

    var body: some View {
        let layout = isLandscape
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        ZStack {
            layout {
                cameraBlock
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(isLandscape ? 0 : 1)
                accessory
            }
            .background(Theme.background.ignoresSafeArea())

            if matchModeActive {
                matchModeOverlay
            }
        }
        .preferredColorScheme(.dark)
        .animation(nil, value: verticalSizeClass)
        .onAppear {
            warpIsPrimary = false
            if liveHints {
                model.scheduleLiveAnalysis()
            }
        }
        .onChange(of: liveHints) { _, isEnabled in
            if isEnabled {
                model.scheduleLiveAnalysis()
            } else {
                model.clearLiveAnalysis()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isLandscape {
                hud
            }
        }
        .sheet(isPresented: $showEndResolution) {
            EndGameResolutionSheet(
                onConfirm: { outcome, white, black in
                    showEndResolution = false
                    model.finishGame(
                        resultOverride: outcome.resultToken,
                        whitePlayer: white,
                        blackPlayer: black
                    )
                },
                onCancel: {
                    showEndResolution = false
                }
            )
        }
        .sheet(isPresented: $showScoreSheet) {
            MoveSheetDrawer(
                sans: model.committedSANs,
                fen: model.engine.fen,
                onDismiss: { showScoreSheet = false }
            )
        }
        .sheet(isPresented: $model.showEditSheet, onDismiss: {
            if model.phase == .awaitingEdit {
                model.scheduleAutoResumeIfNeeded()
            }
        }) {
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
                HStack(alignment: .top, spacing: 8) {
                    if liveHints, liveShowEval {
                        VStack(spacing: 4) {
                            if let analysis = model.liveAnalysis {
                                Text(analysis.evalDisplay)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .accessibilityLabel("Evaluation \(analysis.evalDisplay)")
                            } else if let message = model.liveAnalysisMessage {
                                Text("—")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textSecondary)
                                    .accessibilityLabel(message)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(Theme.textSecondary)
                            }
                        }
                        .frame(width: 44)
                    }
                    DigitalBoardView(
                        fen: model.engine.fen,
                        lastMove: model.engine.lastMoveSquares,
                        bestMove: liveBestArrow
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxHeight: .infinity)

                // Tappable score sheet drawer handle in portrait
                Button {
                    showScoreSheet = true
                } label: {
                    HStack(spacing: 8) {
                        RecentPlyStrip(sans: model.committedSANs)
                        Image(systemName: "list.bullet.clipboard")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
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
                lastMove: model.engine.lastMoveSquares,
                bestMove: liveBestArrow
            )
            .frame(maxWidth: 180, maxHeight: 180)
            .frame(maxWidth: .infinity)
            if liveHints, liveShowEval {
                if let analysis = model.liveAnalysis {
                    Text(analysis.evalDisplay)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                } else if let message = model.liveAnalysisMessage {
                    Text("—")
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.textSecondary)
                }
            }
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
        GeometryReader { proxy in
            ZStack {
                cameraFeed(showOverlays: !warpIsPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if warpIsPrimary {
                    warpFeed
                        .matchedGeometryEffect(id: "warp", in: previewSwap)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                }

                if showFocusReticle, let focusPoint {
                    FocusReticleView()
                        .position(focusPoint)
                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard !warpIsPrimary else { return }
                        let normalized = CGPoint(
                            x: max(0, min(1, location.x / max(1, proxy.size.width))),
                            y: max(0, min(1, location.y / max(1, proxy.size.height)))
                        )
                        focusPoint = location
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            showFocusReticle = true
                        }
                        model.focusCamera(at: normalized)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            try? await Task.sleep(for: .milliseconds(1200))
                            withAnimation(.easeOut(duration: 0.3)) {
                                showFocusReticle = false
                            }
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Tap to focus camera")

                VStack {
                    HStack {
                        Spacer()
                        cornerPIP
                    }
                    Spacer()
                }
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
                    if showBoardGrid {
                        BoardGridOverlay(
                            quad: quad,
                            bufferSize: model.bufferSize,
                            grid: model.refinedGrid
                        )
                    }
                    if showYoloDots {
                        YOLOBaseOverlay(
                            bases: model.yoloPieceBases,
                            quad: quad,
                            bufferSize: model.bufferSize
                        )
                    }
                    if showPieceBoxes {
                        YOLOBoxOverlay(
                            boxes: model.yoloPieceBoxes,
                            quad: quad,
                            bufferSize: model.bufferSize
                        )
                    }
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
            if showOccupancyOverlay {
                OccupancyGridOverlay(
                    occupancy: model.liveOccupancy,
                    orientation: model.orientation
                )
            }
            if showYoloDots {
                YOLOBaseOverlay(bases: model.yoloPieceBases)
            }
            if showPieceBoxes {
                YOLOBoxOverlay(boxes: model.yoloPieceBoxes)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
            if showCaptureDiagnostics, !model.liveDebugLine.isEmpty {
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
                showEndResolution = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.callout.weight(.bold))
                    Text("End")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(Theme.statusRed)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.statusRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.statusRed.opacity(0.3), lineWidth: 1)
                }
            }
            .accessibilityLabel("End game")

            Button {
                model.undoLast()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.callout.weight(.bold))
                    Text("Undo")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(model.canUndo ? Theme.textPrimary : Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                }
            }
            .disabled(!model.canUndo)
            .accessibilityLabel("Undo last move")

            Menu {
                Button {
                    withAnimation {
                        matchModeActive.toggle()
                    }
                } label: {
                    Label(
                        matchModeActive ? "Exit Match Mode" : "Match Mode (Dim Screen)",
                        systemImage: "moon.fill"
                    )
                }
                Button {
                    speakMoves.toggle()
                } label: {
                    Label(
                        "Speak moves",
                        systemImage: speakMoves ? "checkmark" : "speaker.wave.2"
                    )
                }
                Button("Adjust corners") { model.adjustCorners() }
                Button("Fix last move") { model.beginEdit(replacingLast: true) }
                    .disabled(model.committedPlyCount == 0)
                Button("Copy FEN") { model.copyFEN() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    }
            }
            .accessibilityLabel("More actions")
        }
    }

    private var matchModeOverlay: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)

                Text("Match Mode Active")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text("Recording in background. Screen dimmed to preserve battery.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let lastSAN = model.lastSAN {
                    Text("Last: \(lastSAN)")
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: Capsule())
                }

                Button {
                    withAnimation {
                        matchModeActive = false
                    }
                } label: {
                    Text("Tap to Wake")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                }
                .padding(.top, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                matchModeActive = false
            }
        }
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

private struct FocusReticleView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: 56, height: 56)
            Circle()
                .fill(Color.yellow)
                .frame(width: 4, height: 4)
        }
        .allowsHitTesting(false)
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
