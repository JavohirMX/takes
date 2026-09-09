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
final class RecordingSessionViewModel {
    var phase: SessionPhase = .idle
    var quad: Quadrilateral?
    var bufferSize: CGSize = .zero
    var warpedThumbnail: CGImage?
    var orientation: BoardOrientation = .whiteAtBottom
    var proposedFEN = FenCodec.standard
    var classifiedClasses: [ChessSquare: PieceClass] = FenCodec.standardClasses()
    var lastSAN: String?
    var trackingLost = false
    var detectTimedOut = false
    var cameraUnavailable = false
    var isClassifying = false
    var classifierAvailable = false
    var confirmEndGame = false
    var showEditSheet = false
    var shareItems: [Any] = []
    var showShareSheet = false
    var alertMessage: String?
    var lastCommittedOccupancy = Occupancy.standardStart()
    var ambiguousMoves: [Move] = []
    var editReplacesLast = false
    var settleDuration: Duration = .milliseconds(600)
    var previewImage: CGImage?
    var isVideoImport = false

    let engine = GameEngine()
    let pipeline = VisionPipeline()

    private var frameSource: (any FrameSource)?
    private var liveCamera: LiveCameraSource?
    private var consumeTask: Task<Void, Never>?
    private var detectStartedAt: ContinuousClock.Instant?
    private var settle = SettleDetector()
    private var isProcessingFrame = false
    private var lastProcessTime: ContinuousClock.Instant?
    private var pausedForBackground = false
    private var didAutoConfirmVideo = false
    private let imageContext = CIContext()

    var fen: String { engine.fen }
    var pgn: String { engine.pgn }
    var isLegalProposedFEN: Bool { FenCodec.isLegal(proposedFEN) }
    var isStandardStart: Bool { FenCodec.isStandardStart(proposedFEN) }
    var canUndo: Bool { engine.plyCount > 0 && (phase == .recording || phase == .awaitingEdit || phase == .disturbed || phase == .gameOver) }
    var liveCaptureSession: AVCaptureSession? {
        liveCamera?.captureSession
    }

    func newGame() async {
        await teardown()
        isVideoImport = false
        resetGameState()
        let camera = LiveCameraSource()
        liveCamera = camera
        frameSource = camera
        phase = .detectingBoard
        detectStartedAt = ContinuousClock().now
        do {
            try await camera.start()
            cameraUnavailable = false
        } catch CaptureError.cameraUnavailable {
            cameraUnavailable = true
        } catch CaptureError.permissionDenied {
            cameraUnavailable = true
            alertMessage = CaptureError.permissionDenied.errorDescription
        } catch {
            cameraUnavailable = true
            alertMessage = error.localizedDescription
        }
        classifierAvailable = await pipeline.hasClassifier
        startConsuming()
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
            phase = .detectingBoard
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
        await pipeline.setLockedQuad(quad)
        await pipeline.setOrientation(orientation)
        isClassifying = true
        phase = .confirmingStart
        if classifierAvailable, let warpedThumbnail {
            let classes = await pipeline.classifySquares(from: warpedThumbnail)
            if !classes.isEmpty {
                classifiedClasses = classes
                orientation = FenCodec.inferOrientation(from: classes)
                await pipeline.setOrientation(orientation)
                proposedFEN = FenCodec.fen(from: classes)
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
    }

    func useTheseCorners() async {
        await confirmQuad()
    }

    func flipBoard() async {
        orientation = orientation == .whiteAtBottom ? .whiteAtTop : .whiteAtBottom
        classifiedClasses = FenCodec.remapped(classifiedClasses, flippingOrientation: true)
        proposedFEN = FenCodec.fen(from: classifiedClasses)
        await pipeline.setOrientation(orientation)
    }

    func recapture() async {
        guard classifierAvailable, let warpedThumbnail else { return }
        isClassifying = true
        let classes = await pipeline.classifySquares(from: warpedThumbnail)
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
        settle = SettleDetector(config: .init(stableDuration: .milliseconds(SettleSettings.milliseconds)))
        lastSAN = nil
        trackingLost = false
        phase = .recording
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
        Task { await stopCapture() }
    }

    func undoLast() {
        do {
            try engine.undo()
            lastCommittedOccupancy = engine.occupancy()
            lastSAN = engine.formattedLastSAN
            ambiguousMoves = []
            if phase == .awaitingEdit || phase == .gameOver {
                phase = engine.isTerminal ? .gameOver : .recording
            }
        } catch {
            alertMessage = "Nothing to undo."
        }
    }

    func beginEdit(replacingLast: Bool) {
        editReplacesLast = replacingLast && engine.plyCount > 0
        showEditSheet = true
    }

    func applyEdit(san: String) {
        do {
            if editReplacesLast {
                try engine.replaceLast(with: san)
            } else {
                try engine.apply(san: san)
            }
            lastCommittedOccupancy = engine.occupancy()
            lastSAN = engine.formattedLastSAN
            showEditSheet = false
            ambiguousMoves = []
            phase = engine.isTerminal ? .gameOver : .recording
            announceCommit()
        } catch {
            alertMessage = "Couldn’t apply that move. Try another square."
        }
    }

    func handleBackground() {
        pausedForBackground = true
        Task { await liveCamera?.pause() }
        if phase == .recording {
            phase = .disturbed
        }
    }

    func handleForeground() {
        guard pausedForBackground else { return }
        pausedForBackground = false
        guard phase != .idle, phase != .gameOver, phase != .replay else { return }
        Task {
            if isVideoImport { return }
            do {
                try await liveCamera?.start()
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
        await stopCapture()
        frameSource = nil
        liveCamera = nil
        await pipeline.setLockedQuad(nil)
        phase = .idle
    }

    func updateVideoRotation(from scene: UIWindowScene?) {
        guard let orientation = scene?.interfaceOrientation else { return }
        let mapped: AVCaptureVideoOrientation
        switch orientation {
        case .portrait: mapped = .portrait
        case .portraitUpsideDown: mapped = .portraitUpsideDown
        case .landscapeLeft: mapped = .landscapeLeft
        case .landscapeRight: mapped = .landscapeRight
        default: mapped = .portrait
        }
        liveCamera?.updateVideoRotation(interfaceOrientation: mapped)
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
        if let lastProcessTime, frame.timestamp - lastProcessTime < .milliseconds(100) {
            return
        }
        isProcessingFrame = true
        defer { isProcessingFrame = false }
        lastProcessTime = frame.timestamp
        bufferSize = CGSize(
            width: CVPixelBufferGetWidth(frame.buffer),
            height: CVPixelBufferGetHeight(frame.buffer)
        )

        switch phase {
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
        previewImage = image(from: frame.buffer)
        if let quad, let warped = await pipeline.warp(frame, quad: quad) {
            warpedThumbnail = warped.squareImage
        }
    }

    private func handleLive(_ frame: CapturedFrame) async {
        let observation = await pipeline.observation(from: frame, classify: false)
        if let observation {
            trackingLost = false
            quad = observation.quad
            warpedThumbnail = observation.warpedImage
            previewImage = image(from: frame.buffer)
            ingest(observation)
        } else {
            trackingLost = true
            previewImage = image(from: frame.buffer)
        }
    }

    private func ingest(_ observation: BoardObservation) {
        let motion = settle.ingest(observation.occupancy, at: observation.timestamp)
        let inference: InferenceResult
        if case .stable(let occ) = motion, phase == .disturbed {
            let distance = lastCommittedOccupancy.hammingDistance(to: occ)
            if distance > 8 {
                trackingLost = true
                inference = .none
            } else {
                trackingLost = false
                inference = MoveInferrer.infer(
                    delta: VisualDelta(
                        previous: lastCommittedOccupancy,
                        current: occ,
                        observedClasses: observation.classes
                    ),
                    board: engine.board
                )
            }
        } else {
            inference = .none
        }

        let next = SessionReducer.next(phase: phase, motion: motion, inference: inference)
        switch (next, inference) {
        case (.recording, .unique(let move)):
            do {
                try engine.apply(move: move)
                lastCommittedOccupancy = observation.occupancy
                lastSAN = engine.formattedLastSAN
                phase = engine.isTerminal ? .gameOver : .recording
                announceCommit()
                if engine.isTerminal {
                    Task { await stopCapture() }
                }
            } catch {
                phase = .awaitingEdit
            }
        case (.recording, .none):
            phase = .recording
        case (.awaitingEdit, .ambiguous(let moves)):
            ambiguousMoves = moves
            phase = .awaitingEdit
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case (.awaitingEdit, .illegal):
            ambiguousMoves = []
            phase = .awaitingEdit
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        default:
            phase = next
        }
    }

    private func announceCommit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let lastSAN {
            UIAccessibility.post(notification: .announcement, argument: lastSAN)
        }
    }

    private func useStandardPositionClasses() {
        classifiedClasses = FenCodec.standardClasses()
        proposedFEN = FenCodec.standard
    }

    private func occupancyFromClasses() -> Occupancy {
        var occupancy = Occupancy()
        for (square, piece) in classifiedClasses where piece != .empty {
            occupancy.set(square, occupied: true)
        }
        return occupancy
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
        warpedThumbnail = nil
        previewImage = nil
        orientation = .whiteAtBottom
        proposedFEN = FenCodec.standard
        classifiedClasses = FenCodec.standardClasses()
        lastSAN = nil
        trackingLost = false
        detectTimedOut = false
        cameraUnavailable = false
        confirmEndGame = false
        showEditSheet = false
        lastCommittedOccupancy = Occupancy.standardStart()
        ambiguousMoves = []
        engine.resetToStart()
        detectStartedAt = nil
        didAutoConfirmVideo = false
        settle = SettleDetector(config: .init(stableDuration: settleDuration))
        Task {
            await pipeline.setLockedQuad(nil)
            await pipeline.setOrientation(.whiteAtBottom)
        }
    }
}
