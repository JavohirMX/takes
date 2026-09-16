import AVFoundation
import ChessKit
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Observation
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
    var orientation: BoardOrientation = .whiteAtBottom
    var proposedFEN = FenCodec.standard
    var classifiedClasses: [ChessSquare: PieceClass] = FenCodec.standardClasses()
    var lastSAN: String?
    /// Snapshot of `engine.appliedSANs` assigned as a new array on each commit so SwiftUI HUD observes it.
    var committedSANs: [String] = []
    var committedPlyCount: Int { committedSANs.count }
    var trackingLost = false
    var detectTimedOut = false
    var cameraUnavailable = false
    var isClassifying = false
    var classifierAvailable = false
    var pieceDetectorAvailable = false
    var pieceBoxes: [PieceDetection.Box] = []
    var confirmEndGame = false
    var showEditSheet = false
    var shareItems: [Any] = []
    var showShareSheet = false
    var alertMessage: String?
    var lastCommittedOccupancy = Occupancy.standardStart()
    var liveOccupancy = Occupancy.standardStart()
    /// YOLO piece bases in tight playing-surface UV (0…1), for debug dots.
    var yoloPieceBases: [CGPoint] = []
    /// YOLO boxes in tight playing-surface UV, for live debug overlay.
    var yoloPieceBoxes: [PieceDetection.OverlayBox] = []
    var ambiguousMoves: [Move] = []
    var editReplacesLast = false
    var settleDuration: Duration = .milliseconds(600)
    var previewImage: CGImage?
    var isVideoImport = false
    var trackingWeak = false
    /// Set when confirm-time OpenCV snap fails; still allow lock on the coarse quad.
    var gridSnapFailed = false
    var isCaptureRunning = false
    /// Shared with `CameraPreview` so preview layer and sample buffers rotate together.
    var previewRotationAngle: CGFloat = 90
    /// Live capture diagnostics (phase / settle / Hamming / changed squares).
    var liveDebugLine = ""
    /// Brief soft-reject copy after ChessKit fails to apply a unique move.
    var softRejectMessage: String?
    /// Occupancy bits already rejected as unmatched; skip re-inference until they change or TTL expires.
    private var lastIgnoredOccupancy: Occupancy?
    private var lastIgnoredAt: ContinuousClock.Instant?
    private var lastPieceDetectTime: ContinuousClock.Instant?
    private var isPieceDetecting = false

    let engine = GameEngine()
    let pipeline = VisionPipeline()

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
        if classifierAvailable, let warpedThumbnail {
            let classes = await pipeline.classifySquares(from: warpedThumbnail)
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

    func adjustCorners() {
        if quad == nil {
            quad = Quadrilateral.insetRect(in: bufferSize == .zero ? CGSize(width: 1280, height: 720) : bufferSize)
        }
        phase = .calibratingCorners
    }

    func cancelCalibration() {
        phase = .detectingBoard
        detectStartedAt = ContinuousClock().now
        detectTimedOut = false
    }

    func beginCornerDrag() {
        isDraggingCorner = true
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
        let clamped = CGPoint(
            x: min(max(bufferPoint.x, 0), max(bufferSize.width, 1)),
            y: min(max(bufferPoint.y, 0), max(bufferSize.height, 1))
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

    func useTheseCorners() async {
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
        guard classifierAvailable, warpedThumbnail != nil else { return }
        if refinedGrid == nil {
            await refineGridSnappingQuad()
        } else if let current = warpedThumbnail, let grid = OpenCVGridRefiner.refine(current), grid.isMonotonic {
            refinedGrid = grid
            await pipeline.setRefinedGrid(grid)
        }
        guard let current = warpedThumbnail else { return }
        isClassifying = true
        let classes = await pipeline.classifySquares(from: current)
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

    func useStandardStartingPosition() {
        useStandardPositionClasses()
    }

    func startRecording() {
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
        lastCommittedOccupancy = engine.occupancy()
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        occupancyPrior = makeOccupancyPrior()
        settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
        syncCommittedNotation()
        trackingLost = false
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        liveDebugLine = ""
        armFingerprintSnapshot(warmup: 5)
        phase = .recording
        setKeepsScreenAwake(true)
        if let warpedThumbnail {
            Task {
                await pipeline.captureEmptyBaselines(from: warpedThumbnail, occupied: lastCommittedOccupancy)
            }
        }
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

    func finishGame() {
        phase = .gameOver
        setKeepsScreenAwake(false)
        Task { await stopCapture() }
    }

    func undoLast() {
        do {
            try engine.undo()
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
        } catch {
            alertMessage = "Nothing to undo."
        }
    }

    /// Discard a bad settle and keep recording from the last committed position.
    func resumeRecordingAfterReject() {
        ambiguousMoves = []
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        liveOccupancy = lastCommittedOccupancy
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        settle = makeSeededSettle(occupancy: lastCommittedOccupancy)
        armFingerprintSnapshot(warmup: 3)
        phase = .recording
    }

    func beginEdit(replacingLast: Bool) {
        editReplacesLast = replacingLast && committedPlyCount > 0
        showEditSheet = true
    }

    func commit(move: Move) throws {
        try engine.apply(move: move)
        lastCommittedOccupancy = engine.occupancy()
        resetOccupancyTracking(seeding: lastCommittedOccupancy)
        occupancyPrior = makeOccupancyPrior()
        syncCommittedNotation()
        softRejectMessage = nil
        lastIgnoredOccupancy = nil
        lastIgnoredAt = nil
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
        do {
            if editReplacesLast {
                try engine.replaceLast(with: san)
            } else {
                try engine.apply(san: san)
            }
            lastCommittedOccupancy = engine.occupancy()
            resetOccupancyTracking(seeding: lastCommittedOccupancy)
            occupancyPrior = makeOccupancyPrior()
            syncCommittedNotation()
            showEditSheet = false
            ambiguousMoves = []
            softRejectMessage = nil
            lastIgnoredOccupancy = nil
            armFingerprintSnapshot(warmup: 3)
            phase = engine.isTerminal ? .gameOver : .recording
            setKeepsScreenAwake(phase == .recording)
            announceCommit()
        } catch {
            alertMessage = "Couldn’t apply that move. Try another square."
        }
    }

    func handleBackground() {
        // Presenting a fullScreenCover can report a false `.background` scene
        // phase while the app is still active. Only pause the real camera then.
        guard UIApplication.shared.applicationState == .background else { return }
        pausedForBackground = true
        isCaptureRunning = false
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
        case .recording, .disturbed, .awaitingEdit:
            setKeepsScreenAwake(true)
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
            let url = try PGNShareFile.write(pgn: engine.pgn)
            shareItems = [url]
            showShareSheet = true
        } catch {
            alertMessage = "Couldn’t create the PGN file. Copy it instead."
        }
    }

    func copyPGN() {
        UIPasteboard.general.string = engine.pgn
    }

    func copyFEN() {
        UIPasteboard.general.string = engine.fen
    }

    func savedRecordIfNeeded() -> GameRecord? {
        guard engine.plyCount > 0 else { return nil }
        return GameRecord(
            createdAt: .now,
            pgn: engine.pgn,
            finalFen: engine.fen,
            title: GameRecord.defaultTitle(for: .now)
        )
    }

    func teardown() async {
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
        if isVideoImport {
            previewImage = image(from: frame.buffer)
        }

        studioFrameIndex += 1
        if studioFrameIndex % 2 == 0, let heatmapLocalizer {
            mlQuad = await heatmapLocalizer.detect(in: frame.buffer)
            if activeLocalizer == .ml, !isDraggingCorner, let mlQuad {
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
                    if activeLocalizer == .vision {
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
        } else if !isDraggingCorner, activeLocalizer == .vision, let gray = GrayFrame.from(frame.buffer), let current = visionQuad {
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
                liveDebugLine = "warmup \(fingerprintWarmupFramesRemaining)  ham 0  Δ0  ply \(committedPlyCount)  \(lastSAN ?? "-")"
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
            "Δ\(observation.changedSquareCount)",
            "ply \(committedPlyCount)",
            lastSAN ?? "-"
        ]
        if case .skipIgnored = decision {
            debugParts.append("ignored")
        }
        let amb = MoveInferrer.debugSans(for: inference)
        if !amb.isEmpty {
            debugParts.append(amb)
        }
        liveDebugLine = debugParts.joined(separator: "  ")

        let next = SessionReducer.next(phase: phase, motion: motion, inference: inference)
        switch (next, inference) {
        case (.recording, .unique(let moves)):
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
        default:
            if next == .disturbed {
                softRejectMessage = nil
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

    private func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .recording: "rec"
        case .disturbed: "dist"
        case .awaitingEdit: "edit"
        case .gameOver: "over"
        default: "\(phase)"
        }
    }

    private func announceCommit(sans: [String]? = nil) {
        let spoken = sans ?? engine.appliedSANs.last.map { [$0] } ?? []
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !spoken.isEmpty {
            UIAccessibility.post(notification: .announcement, argument: spoken.joined(separator: " "))
        }
        if SpeechSettings.speakMoves {
            let phrase = spoken.map { SANSpeech.speak($0) }.joined(separator: ". ")
            moveSpeaker.speak(phrase)
        }
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
        consumeTask?.cancel()
        consumeTask = nil
        await frameSource?.stop()
        await liveCamera?.stop()
    }

    private func resetGameState() {
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
        trackingLost = false
        detectTimedOut = false
        cameraUnavailable = false
        isCaptureRunning = false
        confirmEndGame = false
        showEditSheet = false
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
}
