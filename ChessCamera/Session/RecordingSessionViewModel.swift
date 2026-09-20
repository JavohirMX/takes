import AVFoundation
import ChessKit
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class RecordingSessionViewModel: Identifiable {
    nonisolated let id = UUID()
    var phase: SessionPhase = .idle
    var quad: Quadrilateral?
    /// Vision rectangle proposal in Board Studio (always updated when Vision fires).
    var visionQuad: Quadrilateral?
    /// Core ML heatmap proposal in Board Studio (nil if model missing or weak peaks).
    var mlQuad: Quadrilateral?
    /// Which proposal drives handles, warp thumb, and Looks good (default Vision).
    var activeLocalizer: BoardLocalizerSource = .vision
    var bufferSize: CGSize = .zero
    var warpedThumbnail: CGImage?
    var refinedGrid: RefinedBoardGrid?
    /// Persistent preview view reused across layout transitions to eliminate AVCaptureSession lag
    let persistentPreviewView = CameraPreviewView()
    var orientation: BoardOrientation = .whiteAtBottom
    var proposedFEN = FenCodec.standard
    var classifiedClasses: [ChessSquare: PieceClass] = FenCodec.standardClasses()
    var lastSAN: String?
    /// Snapshot of `engine.appliedSANs` assigned as a new array on each commit so SwiftUI HUD observes it.
    var committedSANs: [String] = []
    /// Wall-clock think seconds parallel to `committedSANs` (one entry per ply).
    var committedMoveTimes: [TimeInterval] = []
    var committedPlyCount: Int { committedSANs.count }
    var trackingLost = false
    var detectTimedOut = false
    var cameraUnavailable = false
    var isClassifying = false
    var classifierAvailable = false
    var pieceDetectorAvailable = false
    var pieceDetectionAvailable: Bool { classifierAvailable || pieceDetectorAvailable }
    private(set) var isManuallyEdited: Bool = false
    private var recentCommitTimestamps: [ContinuousClock.Instant] = []
    var pieceBoxes: [PieceDetection.Box] = []
    var confirmEndGame = false
    var showEditSheet = false
    var shareItems: [Any] = []
    var showShareSheet = false
    var alertMessage: String?
    var lastCommittedOccupancy = Occupancy.standardStart()
    var liveOccupancy = Occupancy.standardStart()
    /// YOLO piece bases in tight playing-surface UV (0…1), for debug dots.
    var yoloPieceBases: [PieceDetection.BaseDot] = []
    /// YOLO boxes in tight playing-surface UV, for live debug overlay.
    var yoloPieceBoxes: [PieceDetection.OverlayBox] = []
    var ambiguousMoves: [Move] = []
    var editReplacesLast = false
    /// When set, `applyEdit` replaces this ply (0-based) and drops later moves.
    var editTargetPly: Int? = nil
    var settleDuration: Duration = .milliseconds(600)
    var previewImage: CGImage?
    var isVideoImport = false
    var trackingWeak = false
    /// Active while dragging / adjusting corners mid-game or in the corner adjustment overlay.
    var isAdjustingCorners = false
    private var preAdjustmentQuad: Quadrilateral?
    /// Active while mid-game resync is comparing / presenting the resync sheet.
    var isResyncing = false
    var showResyncSheet = false
    /// Squares where vision occupancy/pieces disagree with the digital board.
    var resyncMismatchSquares: [ChessSquare] = []
    /// Confirm before adopting a vision FEN that clears SAN history.
    var confirmAdoptVision = false
    /// Per-session clock preset (defaults from Settings; Confirm Start can override).
    var sessionClockPreset: ClockPreset = GameClockSettings.preset
    let clocks = GameClockController()
    let thinkTimer = MoveThinkTimer()
    private var clockTickTask: Task<Void, Never>?
    /// Set when confirm-time OpenCV snap fails; still allow lock on the coarse quad.
    var gridSnapFailed = false
    var isCaptureRunning = false
    /// Shared with `CameraPreview` so preview layer and sample buffers rotate together.
    var previewRotationAngle: CGFloat = 90
    /// Live capture diagnostics (phase / settle / Hamming / changed squares).
    var liveDebugLine = ""
    /// Brief soft-reject copy after ChessKit fails to apply a unique move.
    var softRejectMessage: String?
    /// Live engine analysis for the current position (optional, settings-gated).
    var liveAnalysis: PositionAnalysis?
    var liveAnalysisMessage: String?
    /// Occupancy bits already rejected as unmatched; skip re-inference until they change or TTL expires.
    private var lastIgnoredOccupancy: Occupancy?
    private var lastIgnoredAt: ContinuousClock.Instant?
    private var lastPieceDetectTime: ContinuousClock.Instant?
    private var isPieceDetecting = false

    let engine = GameEngine()
    let pipeline = VisionPipeline()
    private let analysisEngine: any ChessAnalyzing = AnalysisServiceFactory.make()
    private var liveAnalysisTask: Task<Void, Never>?
    private var analyzingFEN: String?
    private var autoResumeTask: Task<Void, Never>?
    var autoResumeDelayMilliseconds: Int = AutoResumeSettings.delayMilliseconds
    private(set) var consecutiveAutoResumes: Int = 0

    private var frameSource: (any FrameSource)?
    private var liveCamera: LiveCameraSource?
    private var consumeTask: Task<Void, Never>?
    private var detectStartedAt: ContinuousClock.Instant?
    private var settle = SettleDetector()
    private var occupancySmoother = OccupancySmoother()
    private var occupancyPrior = OccupancyPrior.unconstrained
    private let moveSpeaker = MoveSpeaker()
    private var isProcessingFrame = false
    private var lastProcessTime: ContinuousClock.Instant?
    private var pausedForBackground = false
    private var didAutoConfirmVideo = false
    private var pendingFingerprintSnapshot = false
    /// Frames to wait after Start before locking fingerprints (avoids mid-gesture baselines).
    private var fingerprintWarmupFramesRemaining = 0
    private var isDraggingCorner = false
    private var needsTemplateCapture = true
    private var cornerTracker = CornerTracker()
    private var quadConsensus = QuadConsensus()
    private var weakTrackFrames = 0
    private let imageContext = CIContext()
    private let heatmapLocalizer: HeatmapBoardLocalizer? = HeatmapBoardLocalizer.loadBundled()
    private var studioFrameIndex = 0
    nonisolated(unsafe) private var lastSampleBuffer: CVPixelBuffer?
    private var lastPaddedRefineAt: ContinuousClock.Instant?
    private var lastOpenCVSnap: Quadrilateral?
    private let paddedRefineInterval: Duration = .milliseconds(400)
    /// After two similar OpenCV snaps, stop overwriting Studio corners until drag/Rescan/confirm.
    private var paddedRefineSettled = false
    private var pendingStableSnap: Quadrilateral?
    private var stableSnapHits = 0
    private var weakTrackStartedAt: ContinuousClock.Instant?
    private let weakTrackRecoverDuration = BoardStudioRefinePolicy.weakTrackRecoverDuration

    var fen: String { engine.fen }
    var pgn: String { engine.pgn }
    var isLegalProposedFEN: Bool { FenCodec.isLegal(proposedFEN) }
    var isStandardStart: Bool { FenCodec.isStandardStart(proposedFEN) }
    /// True when continuing a saved game that already has moves (must not wipe SANs on Start).
    var isContinuingGame: Bool { savedRecord != nil && engine.plyCount > 0 }
    var canUndo: Bool { committedPlyCount > 0 && (phase == .recording || phase == .awaitingEdit || phase == .disturbed || phase == .gameOver) }
    var liveCaptureSession: AVCaptureSession? {
        liveCamera?.captureSession
    }
    var isHeatmapLocalizerAvailable: Bool { heatmapLocalizer != nil }
    var detectedPieceCount: Int {
        classifiedClasses.values.filter { $0 != .empty }.count
    }

    func newGame() async {
        await startLiveCamera(phase: .boardStudio)
    }

    /// Full-bleed camera + live YOLO boxes. No confirm-start or recording.
    func startPieceStudio() async {
        await startLiveCamera(phase: .pieceStudio)
        pieceBoxes = []
    }

    private func startLiveCamera(phase: SessionPhase) async {
        await teardown()
        isVideoImport = false
        resetGameState()
        let camera = LiveCameraSource()
        liveCamera = camera
        frameSource = camera
        self.phase = phase
        detectStartedAt = ContinuousClock().now
        needsTemplateCapture = true
        cornerTracker.reset()
        quadConsensus.reset()
        weakTrackFrames = 0
        studioFrameIndex = 0
        startConsuming()
        await Task.yield()
        await startCaptureIfNeeded()
        classifierAvailable = await pipeline.hasClassifier
        pieceDetectorAvailable = await pipeline.hasDetector
    }

    func startCaptureIfNeeded() async {
        guard !isVideoImport, let camera = liveCamera else { return }
        if camera.captureSession.isRunning { return }
        do {
            try await camera.start()
            cameraUnavailable = false
            isCaptureRunning = true
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            updateVideoRotation(from: scene)
        } catch CaptureError.cameraUnavailable {
            cameraUnavailable = true
        } catch CaptureError.permissionDenied {
            cameraUnavailable = true
            alertMessage = CaptureError.permissionDenied.errorDescription
        } catch {
            cameraUnavailable = true
            alertMessage = error.localizedDescription
        }
    }

    func importVideo(url: URL) async {
        await teardown()
        isVideoImport = true
        resetGameState()
        let source = AssetVideoSource(url: url)
        frameSource = source
        phase = .importingVideo
        do {
            try await source.start()
            phase = .boardStudio
            detectStartedAt = ContinuousClock().now
            classifierAvailable = await pipeline.hasClassifier
            pieceDetectorAvailable = await pipeline.hasDetector
            startConsuming()
        } catch {
            alertMessage = (error as? CaptureError)?.errorDescription ?? error.localizedDescription
            phase = .idle
        }
    }

    func confirmQuad() async {
        guard let quad else { return }
        await refineGridSnappingQuad()
        await pipeline.setLockedQuad(self.quad ?? quad)
        await pipeline.setOrientation(orientation)
        isClassifying = true
        phase = .confirmingStart
        if pieceDetectionAvailable, let warpedThumbnail {
            let classes = await pipeline.detectPieces(from: warpedThumbnail)
            if !classes.isEmpty {
                let classifiedAs = orientation
                let inferred = FenCodec.inferOrientation(from: classes, classifiedAs: classifiedAs)
                classifiedClasses = FenCodec.remapped(classes, from: classifiedAs, to: inferred)
                orientation = inferred
                await pipeline.setOrientation(orientation)
                proposedFEN = FenCodec.fen(from: classifiedClasses)
            } else {
                useStandardPositionClasses()
            }
        } else {
            useStandardPositionClasses()
        }
        if let warpedThumbnail {
            await pipeline.captureEmptyBaselines(
                from: warpedThumbnail,
                occupied: occupancyFromClasses()
            )
        }
        isClassifying = false
        persistCurrentCalibration()
    }

    /// Save the current board corners + orientation when Remember board setup is on.
    func persistCurrentCalibration() {
        guard BoardCalibrationSettings.rememberSetup else { return }
        guard let quad,
              bufferSize.width > 0,
              bufferSize.height > 0 else { return }
        BoardCalibrationStore.save(
            PersistedBoardCalibration(
                quad: quad,
                orientation: orientation,
                bufferSize: bufferSize
            )
        )
    }

    /// Whether Board Studio can offer “Use last setup”.
    var hasPersistedCalibration: Bool {
        BoardCalibrationSettings.rememberSetup && BoardCalibrationStore.hasSaved
    }

    /// Restore saved corners (scaled to the current buffer) when Remember is on.
    @discardableResult
    func restorePersistedCalibrationIfPossible() async -> Bool {
        guard BoardCalibrationSettings.rememberSetup else { return false }
        guard bufferSize.width > 0, bufferSize.height > 0 else { return false }
        guard let persisted = BoardCalibrationStore.load(),
              let savedOrientation = persisted.orientation else { return false }

        var restored = Quadrilateral(persisted: persisted)
        let savedSize = persisted.bufferSize
        if abs(savedSize.width - bufferSize.width) > 0.5
            || abs(savedSize.height - bufferSize.height) > 0.5 {
            restored = restored.scaled(from: savedSize, to: bufferSize)
        }
        restored = restored.clamped(to: bufferSize)

        quad = restored
        orientation = savedOrientation
        clearOpenCVSnap()
        await pipeline.setOrientation(orientation)
        await pipeline.setLockedQuad(restored)
        return true
    }

    private func refineGridSnappingQuad() async {
        guard let current = quad, let buffer = lastSampleBuffer else {
            refinedGrid = nil
            gridSnapFailed = true
            await pipeline.setRefinedGrid(nil)
            return
        }
        let size = bufferSize.width > 0
            ? bufferSize
            : CGSize(
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer)
            )
        guard let result = PaddedBoardRefiner.refine(quad: current, buffer: buffer, bufferSize: size) else {
            refinedGrid = nil
            gridSnapFailed = true
            await pipeline.setRefinedGrid(nil)
            return
        }
        gridSnapFailed = false
        applyPaddedRefineResult(result, previousQuad: current)
        await pipeline.setLockedQuad(result.snappedQuad)
        await pipeline.setRefinedGrid(result.grid)
        paddedRefineSettled = true
    }

    private func applyPaddedRefineResult(
        _ result: PaddedBoardRefiner.Result,
        previousQuad: Quadrilateral?
    ) {
        let previous = previousQuad ?? quad
        quad = result.snappedQuad
        lastOpenCVSnap = result.snappedQuad
        if activeLocalizer == .vision {
            visionQuad = result.snappedQuad
            if BoardStudioRefinePolicy.shouldRecaptureTemplates(
                previous: previous,
                snapped: result.snappedQuad,
                imageSize: bufferSize
            ) {
                needsTemplateCapture = true
            }
        }
        if let warp = result.tightWarp {
            warpedThumbnail = warp
        }
        refinedGrid = result.grid
    }

    private func maybeRefineWithPaddedOpenCV() async -> Bool {
        guard !paddedRefineSettled,
              !isDraggingCorner,
              let seed = quad,
              let buffer = lastSampleBuffer,
              bufferSize.width > 1 else {
            return false
        }
        if let lastPaddedRefineAt, ContinuousClock.now - lastPaddedRefineAt < paddedRefineInterval {
            return false
        }
        lastPaddedRefineAt = ContinuousClock.now
        guard let result = PaddedBoardRefiner.refine(quad: seed, buffer: buffer, bufferSize: bufferSize) else {
            pendingStableSnap = nil
            stableSnapHits = 0
            return false
        }
        let progress = BoardStudioRefinePolicy.ingestStableSnap(
            pending: pendingStableSnap,
            hits: stableSnapHits,
            candidate: result.snappedQuad,
            imageSize: bufferSize
        )
        pendingStableSnap = progress.pending
        stableSnapHits = progress.hits
        applyPaddedRefineResult(result, previousQuad: seed)
        await pipeline.setRefinedGrid(result.grid)
        if progress.settled {
            paddedRefineSettled = true
            pendingStableSnap = nil
            stableSnapHits = 0
        }
        return result.tightWarp != nil
    }

    private func clearOpenCVSnap() {
        lastOpenCVSnap = nil
        lastPaddedRefineAt = nil
        paddedRefineSettled = false
        pendingStableSnap = nil
        stableSnapHits = 0
    }

    private func restartVisionDetection() {
        visionQuad = nil
        if activeLocalizer == .vision {
            quad = nil
            warpedThumbnail = nil
            refinedGrid = nil
        }
        trackingWeak = false
        needsTemplateCapture = true
        weakTrackFrames = 0
        weakTrackStartedAt = nil
        cornerTracker.reset()
        quadConsensus.reset()
        clearOpenCVSnap()
        detectStartedAt = ContinuousClock().now
        detectTimedOut = false
    }

    func beginAdjustingCorners() {
        preAdjustmentQuad = quad
        if quad == nil {
            let size = bufferSize == .zero ? CGSize(width: 1280, height: 720) : bufferSize
            quad = Quadrilateral.insetRect(in: size)
        }
        isAdjustingCorners = true
    }

    func cancelCornerAdjustment() {
        if let pre = preAdjustmentQuad {
            quad = pre
            Task {
                await pipeline.setLockedQuad(pre)
            }
        }
        isAdjustingCorners = false
        preAdjustmentQuad = nil
    }

    func commitCornerAdjustment() async {
        guard let current = quad else {
            isAdjustingCorners = false
            return
        }
        await refineGridSnappingQuad()
        let finalQuad = self.quad ?? current
        await pipeline.setLockedQuad(finalQuad)
        cornerTracker.reset()
        needsTemplateCapture = true
        trackingLost = false
        lastCommittedOccupancy = engine.occupancy()
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        occupancyPrior = makeOccupancyPrior()
        settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
        armFingerprintSnapshot(warmup: 3)
        if let warpedThumbnail {
            await pipeline.captureEmptyBaselines(from: warpedThumbnail, occupied: lastCommittedOccupancy)
        }
        isAdjustingCorners = false
        preAdjustmentQuad = nil
        persistCurrentCalibration()
    }

    func rotateQuadCornersClockwise() {
        guard let current = quad else { return }
        quad = Quadrilateral(
            topLeft: current.bottomLeft,
            topRight: current.topLeft,
            bottomRight: current.topRight,
            bottomLeft: current.bottomRight
        )
        clearOpenCVSnap()
    }

    func autoDetectCornersInAdjustment() async {
        guard let buffer = lastSampleBuffer else { return }
        let frame = CapturedFrame(buffer: buffer, timestamp: ContinuousClock.now)
        await pipeline.setLockedQuad(nil)
        if let detected = await pipeline.detectQuad(in: frame) {
            quad = detected
            await refineGridSnappingQuad()
            let finalQuad = self.quad ?? detected
            await pipeline.setLockedQuad(finalQuad)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            if let current = quad {
                await pipeline.setLockedQuad(current)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func adjustCorners() {
        if phase == .recording || phase == .disturbed || phase == .awaitingEdit {
            beginAdjustingCorners()
            return
        }
        if quad == nil {
            quad = Quadrilateral.insetRect(in: bufferSize == .zero ? CGSize(width: 1280, height: 720) : bufferSize)
        }
        phase = .calibratingCorners
    }

    func cancelCalibration() {
        if isAdjustingCorners {
            cancelCornerAdjustment()
            return
        }
        phase = .detectingBoard
        detectStartedAt = ContinuousClock().now
        detectTimedOut = false
    }

    func beginCornerDrag() {
        isDraggingCorner = true
        isManuallyEdited = true
        clearOpenCVSnap()
    }

    func finishCornerDrag() {
        isDraggingCorner = false
        needsTemplateCapture = true
        weakTrackFrames = 0
        weakTrackStartedAt = nil
        trackingWeak = false
        clearOpenCVSnap()
    }

    func rescanBoard() async {
        quad = nil
        visionQuad = nil
        mlQuad = nil
        warpedThumbnail = nil
        refinedGrid = nil
        gridSnapFailed = false
        trackingWeak = false
        isManuallyEdited = false
        needsTemplateCapture = true
        weakTrackFrames = 0
        weakTrackStartedAt = nil
        studioFrameIndex = 0
        activeLocalizer = .vision
        cornerTracker.reset()
        quadConsensus.reset()
        clearOpenCVSnap()
        await pipeline.setLockedQuad(nil)
        detectStartedAt = ContinuousClock().now
        detectTimedOut = false
    }

    /// Timeout / manual path: plant editable inset corners for the user to drag.
    func placeManualCorners() {
        let size = bufferSize == .zero ? CGSize(width: 1280, height: 720) : bufferSize
        let inset = Quadrilateral.insetRect(in: size)
        quad = inset
        visionQuad = inset
        activeLocalizer = .vision
        detectTimedOut = true
        needsTemplateCapture = true
        weakTrackFrames = 0
        weakTrackStartedAt = nil
        trackingWeak = false
        cornerTracker.reset()
        quadConsensus.reset()
        clearOpenCVSnap()
    }

    func setActiveLocalizer(_ source: BoardLocalizerSource) {
        switch source {
        case .vision:
            guard visionQuad != nil else { return }
            activeLocalizer = .vision
            quad = visionQuad
        case .ml:
            guard mlQuad != nil else { return }
            activeLocalizer = .ml
            quad = mlQuad
        }
        needsTemplateCapture = true
        weakTrackFrames = 0
        weakTrackStartedAt = nil
        trackingWeak = false
        cornerTracker.reset()
        clearOpenCVSnap()
    }

    func setCorner(_ index: Int, bufferPoint: CGPoint) {
        guard var quad else { return }
        isManuallyEdited = true
        let bounds = (bufferSize.width > 0 && bufferSize.height > 0)
            ? bufferSize
            : CGSize(width: 1280, height: 720)
        let clamped = CGPoint(
            x: min(max(bufferPoint.x, 0), bounds.width),
            y: min(max(bufferPoint.y, 0), bounds.height)
        )
        switch index {
        case 0: quad.topLeft = clamped
        case 1: quad.topRight = clamped
        case 2: quad.bottomRight = clamped
        case 3: quad.bottomLeft = clamped
        default: break
        }
        self.quad = quad
        refinedGrid = nil
        clearOpenCVSnap()
        Task { await pipeline.setRefinedGrid(nil) }
        switch activeLocalizer {
        case .vision: visionQuad = quad
        case .ml: mlQuad = quad
        }
    }

    func selectLocalizer(_ source: BoardLocalizerSource) {
        activeLocalizer = source
        switch source {
        case .vision:
            if let visionQuad { quad = visionQuad }
        case .ml:
            if let mlQuad { quad = mlQuad }
        }
    }

    func continueGame(record: GameRecord) {
        Task { await continueGameAsync(record: record) }
    }

    func continueGameAsync(record: GameRecord) async {
        await teardown()
        isVideoImport = false
        savedRecord = record
        engine.resetToStart()
        let sans = PGNMoveList.sans(from: record.pgn)
        for san in sans {
            try? engine.apply(san: san)
        }
        committedSANs = Array(engine.appliedSANs)
        lastSAN = engine.formattedLastSAN
        committedMoveTimes = record.moveTimes
        if committedMoveTimes.isEmpty {
            let fromPGN = PGNMoveList.emtSeconds(from: record.pgn)
            if fromPGN.count == committedSANs.count {
                committedMoveTimes = fromPGN
            }
        } else if committedMoveTimes.count > committedSANs.count {
            committedMoveTimes = Array(committedMoveTimes.prefix(committedSANs.count))
        }
        lastCommittedOccupancy = engine.occupancy()
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        occupancyPrior = makeOccupancyPrior()
        if let tc = record.timeControl, let matched = GameClockSettings.preset(matchingTimeControl: tc) {
            sessionClockPreset = matched
        } else if record.whiteTimeRemaining != nil || record.blackTimeRemaining != nil {
            sessionClockPreset = .custom
        } else {
            sessionClockPreset = GameClockSettings.preset
        }

        let camera = LiveCameraSource()
        liveCamera = camera
        frameSource = camera
        self.phase = .boardStudio
        detectStartedAt = ContinuousClock().now
        detectTimedOut = false
        needsTemplateCapture = true
        cornerTracker.reset()
        quadConsensus.reset()
        weakTrackFrames = 0
        studioFrameIndex = 0
        startConsuming()
        await Task.yield()
        await startCaptureIfNeeded()
        classifierAvailable = await pipeline.hasClassifier
        pieceDetectorAvailable = await pipeline.hasDetector
    }

    func useTheseCorners() async {
        if isAdjustingCorners {
            await commitCornerAdjustment()
            return
        }
        await confirmQuad()
    }

    func rotateBoard() async {
        let next = orientation.rotatedCounterClockwise
        classifiedClasses = FenCodec.remapped(classifiedClasses, from: orientation, to: next)
        orientation = next
        proposedFEN = FenCodec.fen(from: classifiedClasses)
        await pipeline.setOrientation(orientation)
        needsTemplateCapture = true
    }

    func recapture() async {
        guard pieceDetectionAvailable, warpedThumbnail != nil else { return }
        if refinedGrid == nil {
            await refineGridSnappingQuad()
        } else if let current = warpedThumbnail, let grid = OpenCVGridRefiner.refine(current), grid.isMonotonic {
            refinedGrid = grid
            await pipeline.setRefinedGrid(grid)
        }
        guard let current = warpedThumbnail else { return }
        isClassifying = true
        let classes = await pipeline.detectPieces(from: current)
        if !classes.isEmpty {
            classifiedClasses = classes
            proposedFEN = FenCodec.fen(from: classes)
        }
        isClassifying = false
    }

    func cyclePiece(at square: ChessSquare) {
        let current = classifiedClasses[square] ?? .empty
        classifiedClasses[square] = current.nextCycled()
        proposedFEN = FenCodec.fen(from: classifiedClasses)
    }

    func setPiece(_ piece: PieceClass, at square: ChessSquare) {
        classifiedClasses[square] = piece
        let parts = proposedFEN.components(separatedBy: " ")
        let activeTurn = (parts.count >= 2) ? parts[1] : "w"
        let placement = FenCodec.placement(from: classifiedClasses)
        proposedFEN = "\(placement) \(activeTurn) KQkq - 0 1"
    }

    var sideToMove: Piece.Color {
        let parts = proposedFEN.components(separatedBy: " ")
        if parts.count >= 2 && parts[1] == "b" { return .black }
        return .white
    }

    func setSideToMove(_ color: Piece.Color) {
        let parts = proposedFEN.components(separatedBy: " ")
        guard !parts.isEmpty else { return }
        var mutableParts = parts
        if mutableParts.count < 6 {
            let placement = FenCodec.placement(from: classifiedClasses)
            proposedFEN = "\(placement) \(color == .white ? "w" : "b") KQkq - 0 1"
        } else {
            mutableParts[1] = color == .white ? "w" : "b"
            proposedFEN = mutableParts.joined(separator: " ")
        }
    }

    func useStandardStartingPosition() {
        useStandardPositionClasses()
    }

    func startRecording(mode: StartRecordingMode? = nil) {
        let resolved = mode ?? (isContinuingGame ? .continueOrResync : .newGame)
        switch resolved {
        case .newGame:
            guard FenCodec.isLegal(proposedFEN) else { return }
            do {
                if FenCodec.isStandardStart(proposedFEN) {
                    engine.resetToStart()
                } else {
                    try engine.load(fen: proposedFEN)
                }
            } catch {
                useStandardPositionClasses()
                engine.resetToStart()
            }
            committedMoveTimes = []
        case .continueOrResync:
            // Keep engine + appliedSANs + committedMoveTimes; only re-seed vision.
            break
        }
        lastCommittedOccupancy = engine.occupancy()
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        occupancyPrior = makeOccupancyPrior()
        settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
        syncCommittedNotation()
        trackingLost = false
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        liveDebugLine = ""
        consecutiveAutoResumes = 0
        armFingerprintSnapshot(warmup: 5)
        phase = .recording
        setKeepsScreenAwake(true)
        if let warpedThumbnail {
            Task {
                await pipeline.captureEmptyBaselines(from: warpedThumbnail, occupied: lastCommittedOccupancy)
            }
        }
        configureClocksForSession()
        startThinkForSideToMove()
        scheduleLiveAnalysis()
    }

    /// Mid-game: re-read pieces from the locked warp and compare to the digital board.
    func beginResync() async {
        guard phase == .recording || phase == .disturbed || phase == .awaitingEdit else { return }
        guard !isAdjustingCorners else { return }
        cancelAutoResume()
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        confirmAdoptVision = false
        isResyncing = true

        guard let warpedThumbnail else {
            alertMessage = "Can't see the board yet. Try Adjust corners first."
            isResyncing = false
            return
        }

        isClassifying = true
        var classes: [ChessSquare: PieceClass] = [:]
        if pieceDetectionAvailable {
            classes = await pipeline.detectPieces(from: warpedThumbnail)
        }
        isClassifying = false

        if classes.isEmpty {
            // No piece read — fall back to re-baselining against the digital board.
            await reseedVisionFromEngine()
            isResyncing = false
            return
        }

        classifiedClasses = classes
        let side = engine.fen.split(separator: " ").dropFirst().first.map(String.init) ?? "w"
        proposedFEN = FenCodec.fen(from: classes, sideToMove: side)

        if visionMatchesEngine(classes) {
            await reseedVisionFromEngine()
            isResyncing = false
            return
        }

        resyncMismatchSquares = mismatchSquares(vision: classes)
        showResyncSheet = true
    }

    /// Resolve a mismatch sheet. `trustVision: false` (default) re-baselines to the digital board.
    /// `trustVision: true` loads the proposed/edited FEN and clears move history.
    func applyResync(trustVision: Bool) async {
        if trustVision {
            guard FenCodec.isLegal(proposedFEN) else {
                alertMessage = "That position isn’t a legal FEN."
                return
            }
            do {
                try engine.load(fen: proposedFEN)
            } catch {
                alertMessage = "Couldn’t load that position."
                return
            }
            syncCommittedNotation()
            committedMoveTimes = []
            if let existing = savedRecord {
                existing.pgn = engine.pgn
                existing.finalFen = engine.fen
                existing.openingName = OpeningDetector.detect(sans: committedSANs)
                existing.moveTimes = []
                existing.clearPersistedAnalysis()
            }
        }
        await reseedVisionFromEngine()
        finishResyncUI()
        if phase == .awaitingEdit || phase == .disturbed {
            phase = engine.isTerminal ? .gameOver : .recording
            setKeepsScreenAwake(phase == .recording)
        }
        scheduleLiveAnalysis()
    }

    func cancelResync() {
        finishResyncUI()
    }

    /// After editing pieces in the resync sheet, refresh mismatch list / proposed FEN.
    func refreshResyncProposal() {
        let side = engine.fen.split(separator: " ").dropFirst().first.map(String.init) ?? "w"
        proposedFEN = FenCodec.fen(from: classifiedClasses, sideToMove: side)
        resyncMismatchSquares = mismatchSquares(vision: classifiedClasses)
    }

    /// Whether the edited/vision position’s occupancy matches the engine (history can be kept).
    var resyncOccupancyMatchesEngine: Bool {
        Occupancy.from(classes: classifiedClasses) == engine.occupancy()
    }

    /// Piece-identity match used by the resync sheet “matches digital” affordance.
    var visionPlacementMatchesEngine: Bool {
        FenCodec.placement(from: classifiedClasses) == FenCodec.placement(from: engine.pieceMap())
    }

    private func finishResyncUI() {
        showResyncSheet = false
        isResyncing = false
        confirmAdoptVision = false
        resyncMismatchSquares = []
        isClassifying = false
    }

    /// Re-seed occupancy / prior / settle / fingerprints / baselines from the engine. No engine mutation.
    func reseedVisionFromEngine() async {
        lastCommittedOccupancy = engine.occupancy()
        liveOccupancy = lastCommittedOccupancy
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        occupancyPrior = makeOccupancyPrior()
        settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        lastIgnoredAt = nil
        armFingerprintSnapshot(warmup: 3)
        if let warpedThumbnail {
            await pipeline.captureEmptyBaselines(from: warpedThumbnail, occupied: lastCommittedOccupancy)
        }
    }

    private func visionMatchesEngine(_ classes: [ChessSquare: PieceClass]) -> Bool {
        let visionOcc = Occupancy.from(classes: classes)
        guard visionOcc == engine.occupancy() else { return false }
        let visionPlacement = FenCodec.placement(from: classes)
        let enginePlacement = FenCodec.placement(from: engine.pieceMap())
        return visionPlacement == enginePlacement
    }

    private func mismatchSquares(vision: [ChessSquare: PieceClass]) -> [ChessSquare] {
        let engineMap = engine.pieceMap()
        var squares: [ChessSquare] = []
        for file in 0..<8 {
            for rank in 0..<8 {
                let square = ChessSquare(file: file, rank: rank)
                let v = vision[square] ?? .empty
                let e = engineMap[square] ?? .empty
                if v != e {
                    squares.append(square)
                }
            }
        }
        return squares.sorted { $0.bitIndex < $1.bitIndex }
    }

    func requestEndGame() {
        if engine.isTerminal || engine.plyCount == 0 {
            finishGame()
        } else {
            confirmEndGame = true
        }
    }

    func confirmEndAndSave() {
        confirmEndGame = false
        finishGame()
    }

    var pendingResultOverride: String?
    var pendingWhitePlayer: String?
    var pendingBlackPlayer: String?

    func focusCamera(at normalizedPoint: CGPoint) {
        liveCamera?.focusAndExpose(at: normalizedPoint)
    }

    func finishGame(resultOverride: String? = nil, whitePlayer: String? = nil, blackPlayer: String? = nil) {
        if let resultOverride { pendingResultOverride = resultOverride }
        if let whitePlayer { pendingWhitePlayer = whitePlayer }
        if let blackPlayer { pendingBlackPlayer = blackPlayer }
        if let existing = savedRecord {
            if let resultOverride { existing.resultOverride = resultOverride }
            if let whitePlayer { existing.whitePlayer = whitePlayer }
            if let blackPlayer { existing.blackPlayer = blackPlayer }
        }
        cancelAutoResume()
        stopClockTicker()
        clocks.pause()
        thinkTimer.pauseThink()
        persistClockStateToRecord()
        persistMoveTimesToRecord()
        phase = .gameOver
        setKeepsScreenAwake(false)
        Task { await stopCapture() }
    }

    func undoLast() {
        cancelAutoResume()
        consecutiveAutoResumes = 0
        do {
            try engine.undo()
            if !committedMoveTimes.isEmpty {
                committedMoveTimes.removeLast()
            }
            lastCommittedOccupancy = engine.occupancy()
            resetOccupancyTracking(seeding: lastCommittedOccupancy)
            occupancyPrior = makeOccupancyPrior()
            syncCommittedNotation()
            ambiguousMoves = []
            softRejectMessage = nil
            lastIgnoredOccupancy = nil
            armFingerprintSnapshot(warmup: 3)
            if phase == .awaitingEdit || phase == .gameOver {
                phase = engine.isTerminal ? .gameOver : .recording
                setKeepsScreenAwake(phase == .recording)
            }
            if engine.plyCount == 0 {
                discardSavedRecord()
            } else if let existing = savedRecord {
                existing.pgn = engine.pgn
                existing.finalFen = engine.fen
                existing.moveTimes = committedMoveTimes
                existing.clearPersistedAnalysis()
            }
            scheduleLiveAnalysis()
            startThinkForSideToMove()
        } catch {
            alertMessage = "Nothing to undo."
        }
        syncClockSideToEngine()
    }

    /// Discard a bad settle and keep recording from the last committed position.
    func resumeRecordingAfterReject() {
        cancelAutoResume()
        ambiguousMoves = []
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        liveOccupancy = lastCommittedOccupancy
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
        armFingerprintSnapshot(warmup: 3)
        phase = .recording
    }

    func scheduleAutoResumeIfNeeded() {
        guard AutoResumeSettings.enabled else { return }
        cancelAutoResume()
        guard consecutiveAutoResumes < 4 else { return }

        let delay: Int
        if autoResumeDelayMilliseconds != AutoResumeSettings.delayMilliseconds {
            delay = autoResumeDelayMilliseconds
        } else {
            delay = consecutiveAutoResumes < 2 ? 1000 : 3000
        }

        autoResumeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .awaitingEdit && !self.showEditSheet {
                self.consecutiveAutoResumes += 1
                self.resumeRecordingAfterReject()
            }
        }
    }

    func cancelAutoResume() {
        autoResumeTask?.cancel()
        autoResumeTask = nil
    }

    func beginEdit(replacingLast: Bool) {
        cancelAutoResume()
        consecutiveAutoResumes = 0
        if replacingLast, committedPlyCount > 0 {
            editTargetPly = committedPlyCount - 1
            editReplacesLast = true
        } else {
            editTargetPly = nil
            editReplacesLast = false
        }
        showEditSheet = true
    }

    /// Edit an earlier ply; later moves will be removed when the edit is applied.
    func beginEdit(atPly ply: Int) {
        cancelAutoResume()
        consecutiveAutoResumes = 0
        guard ply >= 0, ply < committedPlyCount else { return }
        editTargetPly = ply
        editReplacesLast = ply == committedPlyCount - 1
        showEditSheet = true
    }

    func commit(move: Move) throws {
        try engine.apply(move: move)
        recentCommitTimestamps.append(ContinuousClock().now)
        consecutiveAutoResumes = 0
        lastCommittedOccupancy = engine.occupancy()
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        occupancyPrior = makeOccupancyPrior()
        syncCommittedNotation()
        let think = thinkTimer.consumeThinkTime()
        committedMoveTimes.append(think)
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        lastIgnoredAt = nil
        if clocks.isEnabled {
            clocks.onMoveCommitted(newSide: clockSide(for: engine.sideToMove))
            persistClockStateToRecord()
        }
        persistMoveTimesToRecord()
        startThinkForSideToMove()
        scheduleLiveAnalysis()
    }

    private func isRateLimited(at now: ContinuousClock.Instant = ContinuousClock().now) -> Bool {
        let limit = AnalysisSettings.moveRateLimit
        guard limit != .off else { return false }
        let window = limit.windowDurationSeconds
        let maxMoves = limit.maxMoves
        recentCommitTimestamps.removeAll { now - $0 > .seconds(window) }
        return recentCommitTimestamps.count >= maxMoves
    }

    private func syncCommittedNotation() {
        committedSANs = Array(engine.appliedSANs)
        lastSAN = engine.formattedLastSAN
    }

    private func resetOccupancyTracking(seeding occupancy: Occupancy) {
        occupancySmoother.reset(seeding: occupancy)
        Task { await pipeline.resetYoloOccupancySmoother(seeding: occupancy) }
    }

    private func makeOccupancyPrior() -> OccupancyPrior {
        GameEngine.occupancyPrior(of: engine.board, includeReplies: FastReplySettings.enabled)
    }

    private func makeSeededSettle(occupancy: Occupancy) -> SettleDetector {
        var detector = SettleDetector(config: .init(
            stableDuration: .milliseconds(SettleSettings.milliseconds),
            maxHammingJitter: 1
        ))
        detector.seed(occupancy: occupancy, at: ContinuousClock().now)
        return detector
    }

    func applyEdit(san: String) {
        cancelAutoResume()
        consecutiveAutoResumes = 0
        let targetPly = editTargetPly
        let replacesLast = editReplacesLast
        do {
            if let ply = targetPly {
                try engine.replace(atPly: ply, with: san)
                committedMoveTimes = Array(committedMoveTimes.prefix(ply))
                committedMoveTimes.append(0)
            } else if replacesLast {
                try engine.replaceLast(with: san)
                if !committedMoveTimes.isEmpty {
                    committedMoveTimes.removeLast()
                }
                committedMoveTimes.append(0)
            } else {
                try engine.apply(san: san)
                committedMoveTimes.append(0)
            }
            lastCommittedOccupancy = engine.occupancy()
            liveOccupancy = lastCommittedOccupancy
            resetOccupancyTracking(seeding: lastCommittedOccupancy)
            occupancyPrior = makeOccupancyPrior()
            settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
            syncCommittedNotation()
            showEditSheet = false
            editTargetPly = nil
            editReplacesLast = false
            ambiguousMoves = []
            softRejectMessage = nil
            lastIgnoredOccupancy = nil
            armFingerprintSnapshot(warmup: 3)
            if engine.plyCount == 0 {
                discardSavedRecord()
            } else if let existing = savedRecord {
                existing.pgn = engine.pgn
                existing.finalFen = engine.fen
                existing.openingName = OpeningDetector.detect(sans: committedSANs)
                existing.moveTimes = committedMoveTimes
                existing.clearPersistedAnalysis()
            }
            phase = engine.isTerminal ? .gameOver : .recording
            setKeepsScreenAwake(phase == .recording)
            announceCommit()
            scheduleLiveAnalysis()
            syncClockSideToEngine()
            startThinkForSideToMove()
        } catch {
            alertMessage = "Couldn’t apply that move. Try another square."
        }
    }

    func handleBackground() {
        cancelAutoResume()
        // Presenting a fullScreenCover can report a false `.background` scene
        // phase while the app is still active. Only pause the real camera then.
        guard UIApplication.shared.applicationState == .background else { return }
        pausedForBackground = true
        isCaptureRunning = false
        clocks.pause()
        thinkTimer.pauseThink()
        Task { await liveCamera?.pause() }
        if phase == .recording {
            phase = .disturbed
        }
    }

    func handleForeground() {
        guard pausedForBackground else { return }
        pausedForBackground = false
        guard phase != .idle, phase != .gameOver, phase != .replay else { return }
        switch phase {
        case .recording, .disturbed:
            setKeepsScreenAwake(true)
        case .awaitingEdit:
            setKeepsScreenAwake(true)
            scheduleAutoResumeIfNeeded()
        default:
            break
        }
        Task {
            if isVideoImport { return }
            do {
                try await liveCamera?.start()
                isCaptureRunning = true
            } catch {
                cameraUnavailable = true
            }
        }
    }

    func exportCrops() {
        guard let warpedThumbnail else {
            alertMessage = "No warped board to export yet."
            return
        }
        do {
            let url = try CropExporter.export(warped: warpedThumbnail, orientation: orientation)
            shareItems = [url]
            showShareSheet = true
        } catch {
            alertMessage = "Couldn’t export crops."
        }
    }

    func sharePGN() {
        do {
            let body: String
            if committedMoveTimes.isEmpty {
                body = engine.pgn
            } else if let record = savedRecord {
                body = record.pgnWithHeaders
            } else {
                body = PGNMoveList.annotatedMovetext(
                    sans: committedSANs,
                    moveTimes: committedMoveTimes,
                    result: engine.resultToken
                )
            }
            let url = try PGNShareFile.write(pgn: body)
            shareItems = [url]
            showShareSheet = true
        } catch {
            alertMessage = "Couldn’t create the PGN file. Copy it instead."
        }
    }

    func copyPGN() {
        if committedMoveTimes.isEmpty {
            UIPasteboard.general.string = engine.pgn
        } else if let record = savedRecord {
            UIPasteboard.general.string = record.pgnWithHeaders
        } else {
            UIPasteboard.general.string = PGNMoveList.annotatedMovetext(
                sans: committedSANs,
                moveTimes: committedMoveTimes,
                result: engine.resultToken
            )
        }
    }

    func copyFEN() {
        UIPasteboard.general.string = engine.fen
    }

    var savedRecord: GameRecord?

    func savedRecordIfNeeded() -> GameRecord? {
        guard engine.plyCount > 0 else { return nil }
        if let existing = savedRecord {
            existing.pgn = engine.pgn
            existing.finalFen = engine.fen
            if let pendingResultOverride { existing.resultOverride = pendingResultOverride }
            if let pendingWhitePlayer { existing.whitePlayer = pendingWhitePlayer }
            if let pendingBlackPlayer { existing.blackPlayer = pendingBlackPlayer }
            persistClockState(to: existing)
            existing.moveTimes = committedMoveTimes
            return existing
        }
        let record = GameRecord(
            createdAt: .now,
            pgn: engine.pgn,
            finalFen: engine.fen,
            title: GameRecord.defaultTitle(for: .now),
            whitePlayer: pendingWhitePlayer,
            blackPlayer: pendingBlackPlayer,
            resultOverride: pendingResultOverride,
            timeControl: clocks.isEnabled ? GameClockSettings.timeControlString(for: sessionClockPreset) : nil,
            whiteTimeRemaining: clocks.isEnabled ? clocks.whiteRemaining : nil,
            blackTimeRemaining: clocks.isEnabled ? clocks.blackRemaining : nil,
            moveTimes: committedMoveTimes.isEmpty ? nil : committedMoveTimes
        )
        savedRecord = record
        return record
    }

    func discardSavedRecord() {
        if let record = savedRecord {
            if let context = record.modelContext {
                context.delete(record)
                try? context.save()
            }
            savedRecord = nil
        }
    }

    func teardown() async {
        liveAnalysisTask?.cancel()
        liveAnalysisTask = nil
        liveAnalysis = nil
        liveAnalysisMessage = nil
        stopClockTicker()
        clocks.pause()
        thinkTimer.pauseThink()
        await analysisEngine.stop()
        consumeTask?.cancel()
        consumeTask = nil
        isPieceDetecting = false
        lastPieceDetectTime = nil
        pieceBoxes = []
        yoloPieceBases = []
        yoloPieceBoxes = []
        await stopCapture()
        frameSource = nil
        liveCamera = nil
        await pipeline.setLockedQuad(nil)
        phase = .idle
        setKeepsScreenAwake(false)
    }

    func updateVideoRotation(from scene: UIWindowScene?) {
        guard let orientation = scene?.interfaceOrientation else { return }
        let angle = LiveCameraSource.rotationAngle(forInterfaceOrientation: orientation)
        previewRotationAngle = angle
        liveCamera?.updateVideoRotation(interfaceOrientation: orientation)
    }

    private func startConsuming() {
        consumeTask?.cancel()
        guard let frameSource else { return }
        consumeTask = Task { [weak self] in
            for await frame in frameSource.frames {
                guard let self, !Task.isCancelled else { break }
                await self.handle(frame: frame)
            }
        }
    }

    private func handle(frame: CapturedFrame) async {
        if isProcessingFrame { return }
        let minInterval: Duration = phase == .boardStudio
            ? .milliseconds(50)
            : .milliseconds(100)
        if let lastProcessTime, frame.timestamp - lastProcessTime < minInterval {
            return
        }
        isProcessingFrame = true
        defer { isProcessingFrame = false }
        lastProcessTime = frame.timestamp
        lastSampleBuffer = frame.buffer
        bufferSize = CGSize(
            width: CVPixelBufferGetWidth(frame.buffer),
            height: CVPixelBufferGetHeight(frame.buffer)
        )

        switch phase {
        case .boardStudio:
            await handleBoardStudio(frame)
        case .pieceStudio:
            schedulePieceBoxDetectIfNeeded(frame.buffer)
        case .detectingBoard:
            await handleDetection(frame)
        case .calibratingCorners:
            await handleCalibrationPreview(frame)
        case .confirmingStart:
            await handleConfirmPreview(frame)
        case .recording, .disturbed:
            await handleLive(frame)
        case .awaitingEdit:
            await handleConfirmPreview(frame)
        default:
            break
        }
    }

    private func handleBoardStudio(_ frame: CapturedFrame) async {
        previewImage = image(from: frame.buffer)

        studioFrameIndex += 1
        if studioFrameIndex % 2 == 0, let heatmapLocalizer {
            mlQuad = await heatmapLocalizer.detect(in: frame.buffer)
            if activeLocalizer == .ml, !isDraggingCorner, !isManuallyEdited, let mlQuad {
                if let snap = lastOpenCVSnap, snap.isSimilar(to: mlQuad, imageSize: bufferSize) {
                    quad = snap
                } else {
                    clearOpenCVSnap()
                    quad = mlQuad
                }
            }
        }

        if visionQuad == nil {
            if let detected = await pipeline.detectQuad(in: frame) {
                if let consensus = quadConsensus.ingest(detected, imageSize: bufferSize) {
                    visionQuad = consensus
                    if activeLocalizer == .vision, !isManuallyEdited {
                        quad = consensus
                        needsTemplateCapture = true
                    }
                    detectTimedOut = false
                }
            }
            if visionQuad == nil,
               let detectStartedAt,
               ContinuousClock().now - detectStartedAt >= .seconds(2) {
                detectTimedOut = true
            }
        } else if !isDraggingCorner, !isManuallyEdited, activeLocalizer == .vision, let gray = GrayFrame.from(frame.buffer), let current = visionQuad {
            if needsTemplateCapture || !cornerTracker.hasTemplates {
                cornerTracker.capture(from: gray, quad: current)
                needsTemplateCapture = false
                trackingWeak = false
                weakTrackFrames = 0
                weakTrackStartedAt = nil
            } else {
                let result = cornerTracker.track(in: gray, from: current)
                if result.minConfidence < 0.55 {
                    weakTrackFrames += 1
                    trackingWeak = true
                    if weakTrackStartedAt == nil {
                        weakTrackStartedAt = ContinuousClock.now
                    }
                    switch BoardStudioRefinePolicy.weakTrackAction(
                        weakFrames: weakTrackFrames,
                        weakStartedAt: weakTrackStartedAt,
                        now: ContinuousClock.now,
                        recoverAfter: weakTrackRecoverDuration
                    ) {
                    case .updateQuad:
                        visionQuad = result.quad
                        quad = result.quad
                    case .freeze:
                        break
                    case .restartVision:
                        restartVisionDetection()
                        return
                    }
                } else {
                    weakTrackFrames = 0
                    weakTrackStartedAt = nil
                    trackingWeak = false
                    visionQuad = result.quad
                    quad = result.quad
                }
            }
        }

        let didRefine = await maybeRefineWithPaddedOpenCV()
        if !didRefine, let quad, let warped = await pipeline.warp(frame, quad: quad) {
            warpedThumbnail = warped.squareImage
        }

        if isVideoImport, phase == .boardStudio, let quad, !didAutoConfirmVideo {
            if ContinuousClock().now - (detectStartedAt ?? ContinuousClock().now) >= .seconds(1) {
                didAutoConfirmVideo = true
                await confirmQuad()
            }
            _ = quad
        }
    }

    private func schedulePieceBoxDetectIfNeeded(_ buffer: CVPixelBuffer) {
        guard pieceDetectorAvailable else { return }
        if isPieceDetecting { return }
        if let lastPieceDetectTime, ContinuousClock.now - lastPieceDetectTime < .milliseconds(150) {
            return
        }
        guard let image = image(from: buffer) else { return }
        isPieceDetecting = true
        lastPieceDetectTime = ContinuousClock.now
        Task { @MainActor in
            defer { isPieceDetecting = false }
            let boxes = await pipeline.detectPieceBoxes(in: image)
            guard phase == .pieceStudio else { return }
            pieceBoxes = boxes
        }
    }

    private func handleDetection(_ frame: CapturedFrame) async {
        if let detected = await pipeline.detectQuad(in: frame) {
            quad = detected
            if let warped = await pipeline.warp(frame, quad: detected) {
                warpedThumbnail = warped.squareImage
                previewImage = image(from: frame.buffer) ?? warped.squareImage
            }
        } else {
            previewImage = image(from: frame.buffer)
        }
        if let detectStartedAt, ContinuousClock().now - detectStartedAt >= .seconds(2), quad == nil {
            detectTimedOut = true
        }
        if isVideoImport, let quad, !didAutoConfirmVideo {
            if ContinuousClock().now - (detectStartedAt ?? ContinuousClock().now) >= .seconds(1) {
                didAutoConfirmVideo = true
                await confirmQuad()
            }
            _ = quad
        }
    }

    private func handleCalibrationPreview(_ frame: CapturedFrame) async {
        previewImage = image(from: frame.buffer)
        if let quad, let warped = await pipeline.warp(frame, quad: quad) {
            warpedThumbnail = warped.squareImage
        }
    }

    private func handleConfirmPreview(_ frame: CapturedFrame) async {
        if let detected = await pipeline.detectQuad(in: frame) {
            quad = detected
            if let warped = await pipeline.warp(frame, quad: detected) {
                warpedThumbnail = warped.squareImage
            }
        }
        previewImage = image(from: frame.buffer)
    }

    private func handleLive(_ frame: CapturedFrame) async {
        if isAdjustingCorners || isResyncing {
            previewImage = image(from: frame.buffer)
            if let quad, let warped = await pipeline.warp(frame, quad: quad) {
                warpedThumbnail = warped.squareImage
            }
            return
        }
        if pendingFingerprintSnapshot {
            if fingerprintWarmupFramesRemaining > 0 {
                fingerprintWarmupFramesRemaining -= 1
                if let preview = await pipeline.observation(
                    from: frame,
                    classify: false,
                    previousOccupancy: lastCommittedOccupancy
                ) {
                    trackingLost = false
                    quad = preview.quad
                    warpedThumbnail = preview.warpedImage
                    previewImage = image(from: frame.buffer)
                    yoloPieceBases = preview.yoloBases
                    yoloPieceBoxes = preview.yoloBoxes
                } else {
                    trackingLost = true
                    previewImage = image(from: frame.buffer)
                    yoloPieceBases = []
                    yoloPieceBoxes = []
                }
                liveOccupancy = lastCommittedOccupancy
                resetOccupancyTracking(seeding: lastCommittedOccupancy)
                liveDebugLine = "warmup \(fingerprintWarmupFramesRemaining)  ham 0  Δ0"
                return
            }
            await pipeline.requestFingerprintSnapshot()
            pendingFingerprintSnapshot = false
        }
        let observation = await pipeline.observation(
            from: frame,
            classify: false,
            previousOccupancy: lastCommittedOccupancy
        )
        if let observation {
            trackingLost = false
            quad = observation.quad
            warpedThumbnail = observation.warpedImage
            previewImage = image(from: frame.buffer)
            await ingest(observation)
        } else {
            trackingLost = true
            previewImage = image(from: frame.buffer)
            yoloPieceBases = []
            yoloPieceBoxes = []
            liveDebugLine = "no observation"
        }
    }

    private func ingest(_ observation: BoardObservation) async {
        yoloPieceBases = observation.yoloBases
        yoloPieceBoxes = observation.yoloBoxes
        let detected = observation.occupancy
        let gated = occupancyPrior.apply(detected: detected, previous: lastCommittedOccupancy)
        let smoothed = occupancySmoother.ingest(gated)
        liveOccupancy = smoothed
        let settleMotion = settle.ingest(smoothed, at: observation.timestamp)
        let hamming = lastCommittedOccupancy.hammingDistance(to: smoothed)
        if hamming > CommitRelativeMotion.maxInferHamming {
            trackingLost = true
        } else {
            trackingLost = false
        }
        if hamming == 0 {
            lastIgnoredOccupancy = nil
            lastIgnoredAt = nil
        }

        var motion = settleMotion
        if hamming == 0, case .disturbed = settleMotion {
            motion = .stable(smoothed)
        }

        let decision = LiveSettleDecision.action(
            phase: phase,
            settleMotion: motion,
            occupancy: smoothed,
            commitHamming: hamming,
            ignored: lastIgnoredOccupancy,
            ignoredAt: lastIgnoredAt,
            now: observation.timestamp
        )
        var inference: InferenceResult = .none
        switch decision {
        case .skipIgnored:
            liveOccupancy = lastCommittedOccupancy
        case .wait:
            break
        case .infer(let occ):
            inference = inferMove(from: occ, classes: observation.classes)
        }

        if inference == .illegal {
            lastIgnoredOccupancy = smoothed
            lastIgnoredAt = observation.timestamp
        }

        liveDebugLine = Self.formatLiveDebugLine(
            phase: phase,
            motion: motion,
            hamming: hamming,
            changedSquareCount: observation.changedSquareCount,
            decision: decision,
            inference: inference,
            lastCommittedOccupancy: lastCommittedOccupancy,
            smoothedOccupancy: smoothed,
            lastIgnoredAt: lastIgnoredAt,
            now: observation.timestamp,
            ambiguousMoves: ambiguousMoves
        )

        let next = SessionReducer.next(phase: phase, motion: motion, inference: inference)
        switch (next, inference) {
        case (.recording, .unique(let moves)):
            if isRateLimited() {
                liveDebugLine = "rate limited"
                break
            }
            do {
                for move in moves {
                    try commit(move: move)
                }
                phase = engine.isTerminal ? .gameOver : .recording
                setKeepsScreenAwake(phase == .recording)
                announceCommit(sans: moves.map(\.san))
                if let warped = observation.warpedImage {
                    await pipeline.snapshotFingerprints(from: warped)
                }
                if engine.isTerminal {
                    Task { await stopCapture() }
                }
            } catch {
                softRejectMessage = "Couldn’t apply that move"
                phase = .recording
                resetOccupancyTracking(seeding: lastCommittedOccupancy)
                settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
                AttentionBeep.play()
            }
        case (.recording, .illegal):
            lastIgnoredOccupancy = smoothed
            lastIgnoredAt = observation.timestamp
            liveOccupancy = lastCommittedOccupancy
            phase = .recording
        case (.recording, .none):
            phase = .recording
        case (.awaitingEdit, .ambiguous(let moves)):
            lastIgnoredOccupancy = nil
            lastIgnoredAt = nil
            ambiguousMoves = moves
            softRejectMessage = nil
            phase = .awaitingEdit
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            AttentionBeep.play()
            scheduleAutoResumeIfNeeded()
        default:
            if next == .disturbed {
                softRejectMessage = nil
            }
            if next == .awaitingEdit {
                scheduleAutoResumeIfNeeded()
            }
            phase = next
        }
    }

    private func inferMove(from occupancy: Occupancy, classes: [ChessSquare: PieceClass]) -> InferenceResult {
        let distance = lastCommittedOccupancy.hammingDistance(to: occupancy)
        if distance == 0 {
            lastIgnoredOccupancy = nil
            lastIgnoredAt = nil
            return .none
        }
        if distance > CommitRelativeMotion.maxInferHamming {
            trackingLost = true
            return .none
        }
        trackingLost = false
        return MoveInferrer.infer(
            delta: VisualDelta(
                previous: lastCommittedOccupancy,
                current: occupancy,
                observedClasses: classes
            ),
            board: engine.board,
            maxPlies: FastReplySettings.enabled ? 2 : 1
        )
    }

    nonisolated static func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .recording: "rec"
        case .disturbed: "dist"
        case .awaitingEdit: "edit"
        case .gameOver: "over"
        default: "\(phase)"
        }
    }

    nonisolated static func formatLiveDebugLine(
        phase: SessionPhase,
        motion: BoardMotion,
        hamming: Int,
        changedSquareCount: Int,
        decision: LiveSettleAction,
        inference: InferenceResult,
        lastCommittedOccupancy: Occupancy,
        smoothedOccupancy: Occupancy,
        lastIgnoredAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        ambiguousMoves: [Move] = []
    ) -> String {
        let motionLabel: String
        switch motion {
        case .stable:
            motionLabel = "stable"
        case .disturbed:
            motionLabel = "disturbed"
        }

        var debugParts = [
            phaseLabel(phase),
            motionLabel,
            "ham \(hamming)",
            "Δ\(changedSquareCount)"
        ]

        let isIgnored = (decision == .skipIgnored) || (inference == .illegal)
        if isIgnored {
            let ignoredTime = lastIgnoredAt ?? now
            let elapsed = now - ignoredTime
            let remaining = max(.zero, LiveSettleDecision.ignoredTTL - elapsed)
            let diffSquares = lastCommittedOccupancy.differingSquares(with: smoothedOccupancy)
            let formattedSquares: String
            if diffSquares.count > 4 {
                formattedSquares = diffSquares.prefix(4).map(\.algebraic).joined(separator: ", ") + "..."
            } else {
                formattedSquares = diffSquares.map(\.algebraic).joined(separator: ", ")
            }
            let sqPart = formattedSquares.isEmpty ? "" : " [\(formattedSquares)]"
            debugParts.append("ignored: illegal delta\(sqPart) (\(String(format: "%.1fs", remaining.inSeconds)))")
        }

        var candidateSans = MoveInferrer.debugSans(for: inference)
        if candidateSans.isEmpty, phase == .awaitingEdit, !ambiguousMoves.isEmpty {
            let sans = ambiguousMoves.prefix(3).map(\.san).joined(separator: ",")
            if !sans.isEmpty {
                candidateSans = "amb \(sans)"
            }
        }
        if !candidateSans.isEmpty {
            debugParts.append(candidateSans)
        }

        return debugParts.joined(separator: "  ")
    }

    private func announceCommit(sans: [String]? = nil) {
        let spoken = sans ?? engine.appliedSANs.last.map { [$0] } ?? []
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let lastMove = spoken.last {
            if lastMove.contains("#") || lastMove.contains("+") {
                ChessAudioFeedback.playCheck()
            } else if lastMove.contains("x") {
                ChessAudioFeedback.playCapture()
            } else {
                ChessAudioFeedback.playMove()
            }
        } else {
            ChessAudioFeedback.playMove()
        }
        if !spoken.isEmpty {
            UIAccessibility.post(notification: .announcement, argument: spoken.joined(separator: " "))
        }
        if SpeechSettings.speakMoves {
            let phrase = spoken.map { SANSpeech.speak($0) }.joined(separator: ". ")
            moveSpeaker.speak(phrase)
        }
        scheduleLiveAnalysis()
    }

    func scheduleLiveAnalysis() {
        guard AnalysisSettings.liveHintsEnabled else {
            clearLiveAnalysis()
            return
        }
        guard phase == .recording || phase == .disturbed || phase == .awaitingEdit || phase == .gameOver else {
            clearLiveAnalysis()
            return
        }
        let fen = engine.fen
        if liveAnalysis?.fen == fen {
            return
        }
        if analyzingFEN == fen, liveAnalysisTask != nil {
            return
        }
        liveAnalysisTask?.cancel()
        analyzingFEN = fen
        liveAnalysis = nil
        let analysisEngine = analysisEngine
        liveAnalysisTask = Task { [weak self] in
            let result = await analysisEngine.analyze(.live(fen: fen))
            guard !Task.isCancelled else { return }
            let availability = result == nil ? await analysisEngine.availability : nil
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.engine.fen == fen else { return }
                self.analyzingFEN = nil
                if let result {
                    self.liveAnalysis = result
                    self.liveAnalysisMessage = nil
                } else {
                    self.liveAnalysis = nil
                    self.liveAnalysisMessage = availability?.userMessage
                }
            }
        }
    }

    func clearLiveAnalysis() {
        liveAnalysisTask?.cancel()
        liveAnalysisTask = nil
        analyzingFEN = nil
        liveAnalysis = nil
        liveAnalysisMessage = nil
    }

    private func setKeepsScreenAwake(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }

    private func useStandardPositionClasses() {
        classifiedClasses = FenCodec.standardClasses()
        proposedFEN = FenCodec.standard
    }

    private func occupancyFromClasses() -> Occupancy {
        Occupancy.from(classes: classifiedClasses)
    }

    private func armFingerprintSnapshot(warmup: Int) {
        pendingFingerprintSnapshot = true
        fingerprintWarmupFramesRemaining = warmup
    }

    private func image(from buffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        return imageContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private func stopCapture() async {
        cancelAutoResume()
        clearLiveAnalysis()
        consumeTask?.cancel()
        consumeTask = nil
        await frameSource?.stop()
        await liveCamera?.stop()
    }

    private func resetGameState() {
        cancelAutoResume()
        clearLiveAnalysis()
        stopClockTicker()
        clocks.configureOff()
        thinkTimer.reset()
        sessionClockPreset = GameClockSettings.preset
        savedRecord = nil
        phase = .idle
        quad = nil
        visionQuad = nil
        mlQuad = nil
        activeLocalizer = .vision
        studioFrameIndex = 0
        lastOpenCVSnap = nil
        lastPaddedRefineAt = nil
        paddedRefineSettled = false
        pendingStableSnap = nil
        stableSnapHits = 0
        lastPieceDetectTime = nil
        isPieceDetecting = false
        pieceBoxes = []
        pieceDetectorAvailable = false
        yoloPieceBases = []
        yoloPieceBoxes = []
        warpedThumbnail = nil
        refinedGrid = nil
        gridSnapFailed = false
        previewImage = nil
        previewRotationAngle = 90
        orientation = .whiteAtBottom
        proposedFEN = FenCodec.standard
        classifiedClasses = FenCodec.standardClasses()
        lastSAN = nil
        committedSANs = []
        committedMoveTimes = []
        consecutiveAutoResumes = 0
        trackingLost = false
        detectTimedOut = false
        cameraUnavailable = false
        isCaptureRunning = false
        confirmEndGame = false
        showEditSheet = false
        editTargetPly = nil
        editReplacesLast = false
        isResyncing = false
        showResyncSheet = false
        resyncMismatchSquares = []
        confirmAdoptVision = false
        lastCommittedOccupancy = Occupancy.standardStart()
        liveOccupancy = Occupancy.standardStart()
        occupancyPrior = OccupancyPrior.unconstrained
        pendingFingerprintSnapshot = false
        trackingWeak = false
        isDraggingCorner = false
        needsTemplateCapture = true
        weakTrackFrames = 0
        weakTrackStartedAt = nil
        cornerTracker.reset()
        quadConsensus.reset()
        ambiguousMoves = []
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        lastIgnoredAt = nil
        liveDebugLine = ""
        engine.resetToStart()
        setKeepsScreenAwake(false)
        detectStartedAt = nil
        didAutoConfirmVideo = false
        settle = makeSeededSettle(occupancy: Occupancy.standardStart())
        occupancySmoother.reset()
        fingerprintWarmupFramesRemaining = 0
        Task {
            await pipeline.setLockedQuad(nil)
            await pipeline.setOrientation(.whiteAtBottom)
            await pipeline.resetYoloOccupancySmoother()
        }
    }

    // MARK: - Game clocks & think timer

    private func configureClocksForSession() {
        stopClockTicker()
        guard !isVideoImport else {
            clocks.configureOff()
            startClockTicker()
            return
        }
        let preset = sessionClockPreset
        guard preset != .off else {
            clocks.configureOff()
            startClockTicker()
            return
        }

        let base: TimeInterval
        let increment: TimeInterval
        if isContinuingGame,
           let record = savedRecord,
           let tc = record.timeControl,
           let parsed = GameClockSettings.parseTimeControl(tc),
           GameClockSettings.timeControlString(for: preset) == tc || preset == .custom {
            base = parsed.base
            increment = parsed.increment
        } else {
            base = GameClockSettings.baseSeconds(for: preset)
            increment = GameClockSettings.incrementSeconds(for: preset)
        }
        guard base > 0 else {
            clocks.configureOff()
            startClockTicker()
            return
        }

        if isContinuingGame,
           let record = savedRecord,
           let white = record.whiteTimeRemaining,
           let black = record.blackTimeRemaining {
            clocks.restore(white: white, black: black, base: base, increment: increment)
            if record.timeControl == nil {
                record.timeControl = GameClockSettings.timeControlString(for: preset)
            }
        } else {
            clocks.configure(base: base, increment: increment)
            if let record = savedRecord {
                record.timeControl = GameClockSettings.timeControlString(for: preset)
                persistClockState(to: record)
            }
        }

        clocks.startIfNeeded(side: clockSide(for: engine.sideToMove))
        startClockTicker()
    }

    private func startClockTicker() {
        stopClockTicker()
        clockTickTask = Task { @MainActor [weak self] in
            let tickInterval: TimeInterval = 0.1
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                self.advanceClocks(delta: tickInterval)
            }
        }
    }

    func stopClockTicker() {
        clockTickTask?.cancel()
        clockTickTask = nil
    }

    /// Pause rules: disturbed / awaitingEdit / background / corner adjust / resync / edit sheet.
    private func clockShouldRun() -> Bool {
        guard clocks.isEnabled, !isVideoImport else { return false }
        return thinkShouldRun()
    }

    /// Same pause gates as clocks, but always available (including clocks Off).
    private func thinkShouldRun() -> Bool {
        guard phase == .recording else { return false }
        guard !pausedForBackground else { return false }
        guard !isAdjustingCorners, !isResyncing, !showEditSheet else { return false }
        return true
    }

    /// Deduct clock time and accumulate think time. Used by the 100 ms ticker and tests.
    func advanceClocks(delta: TimeInterval) {
        if thinkShouldRun() {
            if !thinkTimer.isRunning {
                thinkTimer.resumeThinkIfNeeded()
            }
            thinkTimer.tick(delta: delta)
        } else {
            thinkTimer.pauseThink()
        }

        guard clocks.isEnabled else { return }
        if clockShouldRun() {
            if !clocks.isRunning {
                clocks.startIfNeeded(side: clockSide(for: engine.sideToMove))
            }
            if let flagged = clocks.tick(delta: delta) {
                let result = flagged == .white ? "0-1" : "1-0"
                finishGame(resultOverride: result)
            } else {
                persistClockStateToRecord()
            }
        } else {
            clocks.pause()
        }
    }

    private func persistClockStateToRecord() {
        guard let record = savedRecord else { return }
        persistClockState(to: record)
    }

    private func persistMoveTimesToRecord() {
        guard let record = savedRecord else { return }
        record.moveTimes = committedMoveTimes
    }

    private func persistClockState(to record: GameRecord) {
        if clocks.isEnabled {
            if record.timeControl == nil {
                record.timeControl = GameClockSettings.timeControlString(for: sessionClockPreset)
            }
            record.whiteTimeRemaining = clocks.whiteRemaining
            record.blackTimeRemaining = clocks.blackRemaining
        } else {
            record.timeControl = nil
            record.whiteTimeRemaining = nil
            record.blackTimeRemaining = nil
        }
    }

    private func clockSide(for color: Piece.Color) -> ClockSide {
        color == .white ? .white : .black
    }

    private func startThinkForSideToMove() {
        thinkTimer.startThink(for: clockSide(for: engine.sideToMove))
        if !thinkShouldRun() {
            thinkTimer.pauseThink()
        }
    }

    private func syncClockSideToEngine() {
        guard clocks.isEnabled else { return }
        let side = clockSide(for: engine.sideToMove)
        clocks.setActiveSide(side)
        if clockShouldRun() {
            clocks.startIfNeeded(side: side)
        } else {
            clocks.pause()
        }
    }
}
