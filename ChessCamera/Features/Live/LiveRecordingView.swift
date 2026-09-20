import ChessKit
import SwiftUI
import UIKit

enum LiveViewMode: String, CaseIterable {
    case boardFocus   // Dual preview cards (Camera + Live Board) + full digital board
    case cameraFocus  // Full-screen view of camera or warped board
}

enum FullScreenFeed {
    case camera
    case warp
}

struct LiveRecordingView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewMode: LiveViewMode = .boardFocus
    @State private var fullScreenFeed: FullScreenFeed = .camera

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
    @State private var pendingEditPly: Int?
    @State private var showEditEarlierConfirm = false

    private let topBarHeight: CGFloat = 40
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isExpanded: Bool { viewMode == .cameraFocus }
    private var showsClocks: Bool { model.clocks.isEnabled && !model.isVideoImport }

    private var liveBestArrow: BoardArrow? {
        guard liveHints else { return nil }
        guard model.phase == .recording || model.phase == .disturbed || model.phase == .awaitingEdit || model.phase == .gameOver else { return nil }
        return model.liveAnalysis?.bestArrow
    }

    private var liveBestSAN: String? {
        guard liveHints, let uci = model.liveAnalysis?.bestMoveUCI else { return nil }
        let formatted = PVFormatter.format(fen: model.engine.fen, uciMoves: [uci])
        return formatted.isEmpty ? uci : formatted
    }

    var body: some View {
        ZStack {
            if model.isAdjustingCorners {
                cornerAdjustmentView
                    .transition(.opacity)
            } else if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }

            if matchModeActive && !model.isAdjustingCorners {
                matchModeOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isAdjustingCorners)
        .preferredColorScheme(.dark)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
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
                moveTimes: model.committedMoveTimes,
                onDismiss: { showScoreSheet = false },
                onEditPly: { ply in
                    requestEditPly(ply)
                }
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
        .sheet(isPresented: $model.showResyncSheet, onDismiss: {
            if model.isResyncing {
                model.cancelResync()
            }
        }) {
            ResyncBoardSheet(model: model)
        }
        .confirmationDialog(
            "Moves after this will be removed",
            isPresented: $showEditEarlierConfirm,
            titleVisibility: .visible
        ) {
            Button("Edit move", role: .destructive) {
                if let ply = pendingEditPly {
                    showScoreSheet = false
                    model.beginEdit(atPly: ply)
                }
                pendingEditPly = nil
            }
            Button("Cancel", role: .cancel) {
                pendingEditPly = nil
            }
        } message: {
            if let ply = pendingEditPly, ply + 1 < model.committedSANs.count {
                Text("Editing move \(ply + 1) removes all later moves from the score sheet.")
            } else {
                Text("Replace this move on the score sheet.")
            }
        }
    }

    private func requestEditPly(_ ply: Int) {
        guard ply >= 0, ply < model.committedSANs.count else { return }
        if ply == model.committedSANs.count - 1 {
            showScoreSheet = false
            model.beginEdit(atPly: ply)
            return
        }
        pendingEditPly = ply
        showEditEarlierConfirm = true
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        GeometryReader { proxy in
            let compactHeight = min(150, max(125, proxy.size.height * 0.18))

            ZStack(alignment: .top) {
                if !isExpanded {
                    // Board-first view with dual side-by-side previews at top
                    VStack(spacing: 10) {
                        topBar
                            .frame(height: topBarHeight)

                        // Dual Previews: Live Camera Feed (left) + Rectified Live Board (right)
                        dualPreviewSection(height: compactHeight)

                        // Information Strip (Awaiting Edit Warning, or Opening)
                        if model.phase == .awaitingEdit {
                            awaitingEditAlert
                        } else if let opening = OpeningDetector.detect(sans: model.committedSANs) {
                            openingPill(opening: opening)
                        }

                        // FULL DIGITAL CHESSBOARD
                        boardSection(maxHeight: max(220, proxy.size.height * 0.46))

                        Spacer(minLength: 4)

                        // Moves Drawer & Bottom Controls
                        movesDrawerButton
                        bottomControls
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                } else {
                    // Full-screen focused view of the selected feed
                    fullScreenFocusedView(size: proxy.size)
                }
            }
            .animation(.snappy(duration: 0.15), value: isExpanded)
        }
    }

    // MARK: - Dual Side-by-Side Previews (Camera + Warped Board)

    private func dualPreviewSection(height: CGFloat) -> some View {
        HStack(spacing: 10) {
            // Left Tile: Live Camera Feed (shows physical camera & quad overlay)
            ZStack(alignment: .topTrailing) {
                cameraFeed(showOverlays: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Clean expand indicator
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8) }
                    .padding(6)

                if showCaptureDiagnostics, !model.liveDebugLine.isEmpty {
                    Text(model.liveDebugLine)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                fullScreenFeed = .camera
                viewMode = .cameraFocus
            }
            .accessibilityLabel("Full screen camera preview")

            // Right Tile: Rectified Live Board (1:1 square preview showing occupancy & detections)
            ZStack(alignment: .topTrailing) {
                warpFeed
                    .frame(width: height, height: height)

                // Clean expand indicator
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8) }
                    .padding(6)
            }
            .frame(width: height, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                fullScreenFeed = .warp
                viewMode = .cameraFocus
            }
            .accessibilityLabel("Full screen board preview")
        }
        .frame(height: height)
    }

    // MARK: - Full Screen View

    private func fullScreenFocusedView(size: CGSize) -> some View {
        ZStack {
            // Full Screen Feed background: Tap ANYWHERE on background to toggle between camera and warped board!
            Group {
                if fullScreenFeed == .camera {
                    cameraFeed(showOverlays: true)
                } else {
                    warpFeed
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                fullScreenFeed = (fullScreenFeed == .camera) ? .warp : .camera
            }

            VStack(spacing: 12) {
                // Top control bar
                HStack {
                    statusDot

                    Spacer()

                    GlassCircleButton(
                        icon: "arrow.down.right.and.arrow.up.left",
                        title: "Exit Full Screen",
                        diameter: 40
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewMode = .boardFocus
                    }

                    GlassCircleButton(
                        icon: liveHints ? "cpu.fill" : "cpu",
                        title: "Analysis",
                        diameter: 40,
                        isActive: liveHints
                    ) {
                        liveHints.toggle()
                    }

                    moreMenuButton(size: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                // Floating PiPs: Mini Digital Board (left) and Alternate Feed (right)
                HStack(alignment: .bottom) {
                    // Left: Mini Digital Board -> Tapping returns to Big Board view!
                    ZStack {
                        DigitalBoardView(
                            fen: model.engine.fen,
                            lastMove: model.engine.lastMoveSquares,
                            bestMove: liveBestArrow,
                            interactive: false
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                    }
                    .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewMode = .boardFocus
                    }
                    .accessibilityLabel("Return to board view")

                    Spacer()

                    // Right: Alternate Feed PiP -> Tapping swaps Camera and Warped Board feeds!
                    ZStack {
                        if fullScreenFeed == .camera {
                            warpFeed
                        } else {
                            cameraStill
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                    }
                    .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        fullScreenFeed = (fullScreenFeed == .camera) ? .warp : .camera
                    }
                    .accessibilityLabel(fullScreenFeed == .camera ? "Show warped board" : "Show camera")
                }
                .padding(.horizontal, 16)

                // Bottom HUD
                HStack(spacing: 16) {
                    GlassCircleButton(
                        icon: "stop.circle.fill",
                        title: "End",
                        diameter: 48,
                        isDestructive: true
                    ) {
                        showEndResolution = true
                    }

                    GlassCircleButton(
                        icon: "arrow.uturn.backward",
                        title: "Undo",
                        diameter: 48,
                        isDisabled: !model.canUndo
                    ) {
                        model.undoLast()
                    }

                    Spacer()

                    Button {
                        showScoreSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            RecentPlyStrip(sans: model.committedSANs, maxPlies: 3)
                            Image(systemName: "list.bullet.clipboard")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay { Capsule().strokeBorder(Theme.border.opacity(0.4), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Minimal recording status dot with soft glow aura (no text badge)
            statusDot

            if showsClocks {
                dualClockDisplay
            }

            Spacer(minLength: 4)

            // Quick live analysis toggle using the CPU chess engine icon
            GlassCircleButton(
                icon: liveHints ? "cpu.fill" : "cpu",
                title: "Engine Analysis",
                diameter: 38,
                isActive: liveHints
            ) {
                liveHints.toggle()
            }

            moreMenuButton(size: 38)
        }
    }

    private var dualClockDisplay: some View {
        HStack(spacing: 6) {
            clockChip(
                label: "W",
                remaining: model.clocks.whiteRemaining,
                isActive: model.clocks.activeSide == .white && model.clocks.isRunning
            )
            clockChip(
                label: "B",
                remaining: model.clocks.blackRemaining,
                isActive: model.clocks.activeSide == .black && model.clocks.isRunning
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "White \(GameClockController.format(remaining: model.clocks.whiteRemaining)), Black \(GameClockController.format(remaining: model.clocks.blackRemaining))"
        )
    }

    private func clockChip(label: String, remaining: TimeInterval, isActive: Bool) -> some View {
        let caution = remaining < 30
        let foreground: Color = {
            if caution { return Theme.caution }
            if isActive { return Theme.textPrimary }
            return Theme.textSecondary
        }()
        return HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isActive ? Theme.accent : Theme.textTertiary)
            Text(GameClockController.format(remaining: remaining))
                .font(.caption.monospacedDigit().weight(isActive ? .bold : .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isActive ? Theme.accent.opacity(0.18) : Theme.surfaceMuted,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    caution ? Theme.caution.opacity(0.55)
                        : (isActive ? Theme.accent.opacity(0.45) : Theme.border.opacity(0.35)),
                    lineWidth: 1
                )
        }
    }

    private var statusDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusIndicatorColor)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(statusIndicatorColor.opacity(0.35), lineWidth: 3)
                        .scaleEffect(1.35)
                }

            if model.trackingLost {
                Text("Lost")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(4)
        .accessibilityLabel(statusSummaryText)
    }

    private var statusIndicatorColor: Color {
        if model.trackingLost { return Theme.danger }
        switch model.phase {
        case .recording: return Theme.accent
        case .disturbed: return Theme.caution
        case .awaitingEdit: return Theme.danger
        default: return Theme.accent
        }
    }

    private var statusSummaryText: String {
        if model.trackingLost { return "Tracking Lost" }
        switch model.phase {
        case .disturbed:
            if let san = model.lastSAN, !san.isEmpty {
                return "\(san) · Waiting…"
            }
            return "Waiting for board…"
        case .awaitingEdit:
            return "Needs Attention"
        case .recording:
            if case .check = model.engine.state {
                return "Check (\(model.lastSAN ?? ""))"
            }
            if let san = model.lastSAN {
                return "Move \(model.committedPlyCount): \(san)"
            }
            return "Recording"
        case .gameOver:
            return "Game Over"
        default:
            return "Recording"
        }
    }

    private func boardSection(maxHeight: CGFloat) -> some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = min(proxy.size.height, maxHeight)
            let evalWidth: CGFloat = liveHints ? 30 : 0
            let boardSide = min(availableWidth - evalWidth - (liveHints ? 8 : 0), availableHeight)

            HStack(alignment: .center, spacing: 8) {
                if liveHints {
                    EvalBarView(
                        score: model.liveAnalysis?.score,
                        height: boardSide
                    )
                }

                DigitalBoardView(
                    fen: model.engine.fen,
                    lastMove: model.engine.lastMoveSquares,
                    bestMove: liveBestArrow
                )
                .frame(width: boardSide, height: boardSide)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: maxHeight)
    }

    private func openingPill(opening: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed.fill")
                .font(.caption2)
            Text(opening)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var awaitingEditAlert: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text("Couldn't read move")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Resume") {
                model.resumeRecordingAfterReject()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surfaceMuted, in: Capsule())

            Button("Fix") {
                model.beginEdit(replacingLast: false)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.danger, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.4), lineWidth: 1)
        }
    }

    private var movesDrawerButton: some View {
        Button {
            showScoreSheet = true
        } label: {
            HStack(spacing: 8) {
                RecentPlyStrip(sans: model.committedSANs)
                Image(systemName: "list.bullet.clipboard")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.4), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomControls: some View {
        HStack(spacing: 16) {
            GlassCircleButton(
                icon: "stop.circle.fill",
                title: "End",
                diameter: 48,
                isDestructive: true
            ) {
                showEndResolution = true
            }
            .accessibilityLabel("End game")

            GlassCircleButton(
                icon: "arrow.uturn.backward",
                title: "Undo",
                diameter: 48,
                isDisabled: !model.canUndo
            ) {
                model.undoLast()
            }
            .accessibilityLabel("Undo last move")

            Spacer()

            GlassCircleButton(
                icon: "list.bullet",
                title: "Moves",
                diameter: 48
            ) {
                showScoreSheet = true
            }
            .accessibilityLabel("View moves")
        }
    }

    private func moreMenuButton(size: CGFloat) -> some View {
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
            Button {
                model.beginAdjustingCorners()
            } label: {
                Label("Adjust corners", systemImage: "crop")
            }
            Button {
                Task { await model.beginResync() }
            } label: {
                Label("Resync board", systemImage: "arrow.triangle.2.circlepath")
            }
            Button("Fix last move") { model.beginEdit(replacingLast: true) }
                .disabled(model.committedPlyCount == 0)
            Button("Copy FEN") { model.copyFEN() }
        } label: {
            GlassCircleButton(
                icon: "ellipsis",
                title: "More",
                diameter: size
            ) {}
        }
        .accessibilityLabel("More actions")
    }


    // MARK: - Landscape Layout

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            cameraFeed(showOverlays: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            landscapeSidebar
        }
    }

    private var landscapeSidebar: some View {
        VStack(spacing: 10) {
            topBar

            HStack(spacing: 8) {
                if liveHints {
                    EvalBarView(
                        score: model.liveAnalysis?.score,
                        height: 180
                    )
                }

                DigitalBoardView(
                    fen: model.engine.fen,
                    lastMove: model.engine.lastMoveSquares,
                    bestMove: liveBestArrow
                )
                .frame(maxWidth: 180, maxHeight: 180)
            }
            .frame(maxWidth: .infinity)

            MoveListView(
                sans: model.committedSANs,
                moveTimes: model.committedMoveTimes,
                onEditPly: { ply in
                    requestEditPly(ply)
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomControls
        }
        .padding(16)
        .frame(minWidth: 340, maxWidth: 400)
        .frame(maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Feeds

    private func cameraFeed(showOverlays: Bool) -> some View {
        ZStack {
            CameraPreview(
                session: model.liveCaptureSession,
                stillImage: model.previewImage,
                videoRotationAngle: model.previewRotationAngle,
                customPreviewView: model.persistentPreviewView
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

    private var warpFeed: some View {
        ZStack {
            if let thumb = model.warpedThumbnail {
                Image(uiImage: UIImage(cgImage: thumb))
                    .resizable()
                    .interpolation(.medium)
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

    private var cameraStill: some View {
        ZStack {
            if let preview = model.previewImage {
                Image(uiImage: UIImage(cgImage: preview))
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                Theme.surfaceMuted
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Match Mode

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

    // MARK: - Corner Adjustment Overlay

    private var cornerAdjustmentView: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Persistent Camera Preview (reusing existing UIView)
                CameraPreview(
                    session: model.liveCaptureSession,
                    stillImage: model.isVideoImport ? model.previewImage : nil,
                    videoRotationAngle: model.previewRotationAngle,
                    customPreviewView: model.persistentPreviewView
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

                // Real-time Chessboard Perspective Grid Overlay
                if let quad = model.quad, model.bufferSize.width > 0 {
                    BoardGridOverlay(
                        quad: quad,
                        bufferSize: model.bufferSize,
                        grid: model.refinedGrid,
                        color: Theme.accent.opacity(0.85)
                    )

                    // Draggable Corner Handles with Magnification Loupe
                    cornerHandles(in: size)
                }

                // Top & Bottom Floating Controls
                VStack {
                    cornerAdjustmentHeader
                    Spacer()
                    cornerAdjustmentBottomBar
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var cornerAdjustmentHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crop")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Adjust Board Corners")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Drag corners to align with board")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            }

            Spacer()

            // Quick Auto-Detect button
            GlassCircleButton(
                icon: "wand.and.stars",
                title: "Auto",
                diameter: 38
            ) {
                Task {
                    await model.autoDetectCornersInAdjustment()
                }
            }
            .accessibilityLabel("Auto-detect board corners")

            // Quick Rotate 90 deg clockwise
            GlassCircleButton(
                icon: "rotate.right",
                title: "Rotate",
                diameter: 38
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.rotateQuadCornersClockwise()
            }
            .accessibilityLabel("Rotate corners clockwise")
        }
    }

    private var cornerAdjustmentBottomBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                model.cancelCornerAdjustment()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                }
            }
            .accessibilityLabel("Cancel corner adjustment")

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                Task {
                    await model.commitCornerAdjustment()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("Done")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.accent.opacity(0.4), radius: 8, x: 0, y: 3)
            }
            .accessibilityLabel("Save corners and resume game")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func cornerHandles(in size: CGSize) -> some View {
        if let quad = model.quad, model.bufferSize.width > 0 {
            let points = [
                VideoMapping.bufferToView(point: quad.topLeft, viewSize: size, bufferSize: model.bufferSize),
                VideoMapping.bufferToView(point: quad.topRight, viewSize: size, bufferSize: model.bufferSize),
                VideoMapping.bufferToView(point: quad.bottomRight, viewSize: size, bufferSize: model.bufferSize),
                VideoMapping.bufferToView(point: quad.bottomLeft, viewSize: size, bufferSize: model.bufferSize)
            ]
            let labels = ["1 (TL)", "2 (TR)", "3 (BR)", "4 (BL)"]
            ForEach(0..<4, id: \.self) { index in
                CornerHandle(
                    label: labels[index],
                    point: points[index],
                    image: model.previewImage,
                    viewSize: size,
                    onDrag: { location in
                        model.beginCornerDrag()
                        let clamped = VideoMapping.clampToVideo(
                            point: location,
                            viewSize: size,
                            bufferSize: model.bufferSize
                        )
                        if let bufferPoint = VideoMapping.viewToBuffer(
                            point: clamped,
                            viewSize: size,
                            bufferSize: model.bufferSize
                        ) {
                            model.setCorner(index, bufferPoint: bufferPoint)
                        }
                    },
                    onEnded: {
                        model.finishCornerDrag()
                    }
                )
            }
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
