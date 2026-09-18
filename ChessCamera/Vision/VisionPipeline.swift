import CoreGraphics
import CoreVideo
import Foundation

struct BoardObservation: Sendable {
    var timestamp: ContinuousClock.Instant
    var quad: Quadrilateral
    var occupancy: Occupancy
    var classes: [ChessSquare: PieceClass]
    /// Fingerprint change-detector count this frame (0 without a snapshot / heuristic fallback).
    var changedSquareCount: Int
    /// YOLO piece bases in tight playing-surface UV (0…1). Empty without a detector.
    var yoloBases: [PieceDetection.BaseDot] = []
    /// YOLO boxes in tight playing-surface UV. Empty without a detector.
    var yoloBoxes: [PieceDetection.OverlayBox] = []
    nonisolated(unsafe) var warpedImage: CGImage?
}

actor VisionPipeline {
    var lockedQuad: Quadrilateral?
    var orientation: BoardOrientation = .whiteAtBottom
    var occupancyEstimator = HeuristicOccupancyEstimator()
    var refinedGrid: RefinedBoardGrid?

    private let localizer: any BoardLocalizer
    private let classifier: (any PieceClassifier)?
    private let detector: (any PieceDetector)?
    private var needsFingerprintSnapshot = false
    /// Pre-fusion YOLO vote: 3 hits to fill, 5 misses to clear.
    private var yoloOccupancySmoother = OccupancySmoother(emptyConfirmFrames: 5, fillConfirmFrames: 3)

    init(
        localizer: any BoardLocalizer = VisionBoardLocalizer(),
        classifier: (any PieceClassifier)? = CoreMLPieceClassifier.loadBundled(),
        detector: (any PieceDetector)? = CoreMLPieceDetector.loadBundled()
    ) {
        self.localizer = localizer
        self.classifier = classifier
        self.detector = detector
    }

    var hasClassifier: Bool { classifier != nil }
    var hasDetector: Bool { detector != nil }

    func setLockedQuad(_ quad: Quadrilateral?) {
        lockedQuad = quad
        if quad == nil {
            refinedGrid = nil
        }
    }

    func setRefinedGrid(_ grid: RefinedBoardGrid?) {
        refinedGrid = grid
    }

    func setOrientation(_ orientation: BoardOrientation) {
        self.orientation = orientation
    }

    func requestFingerprintSnapshot() {
        needsFingerprintSnapshot = true
    }

    func resetYoloOccupancySmoother(seeding occupancy: Occupancy? = nil) {
        yoloOccupancySmoother.reset(seeding: occupancy)
    }

    func captureEmptyBaselines(from warped: CGImage, occupied: Occupancy) {
        let crops = GridSampler.crops(from: warped, orientation: orientation)
        occupancyEstimator.captureBaselines(crops: crops, occupied: occupied)
    }

    func snapshotFingerprints(from warped: CGImage) {
        let crops = GridSampler.crops(from: warped, orientation: orientation)
        occupancyEstimator.snapshot(crops: crops)
        needsFingerprintSnapshot = false
    }

    /// Mounted path: once confirmed, never re-detect — return the locked quad every frame.
    /// Re-detect only after `setLockedQuad(nil)` (Rescan).
    func detectQuad(in frame: CapturedFrame) async -> Quadrilateral? {
        if let locked = lockedQuad {
            return locked
        }
        return await localizer.detect(in: frame.buffer)
    }

    func warp(_ frame: CapturedFrame, quad: Quadrilateral) -> WarpedBoard? {
        BoardWarper.warp(frame.buffer, quad: quad, size: 512)
    }

    func detectPieceBoxes(in image: CGImage) async -> [PieceDetection.Box] {
        guard let detector else { return [] }
        return await detector.detectBoxes(in: image)
    }

    func classifySquares(from warped: CGImage) async -> [ChessSquare: PieceClass] {
        guard let classifier else { return [:] }
        let crops = GridSampler.crops(from: warped, orientation: orientation)
        var classes: [ChessSquare: PieceClass] = [:]
        for crop in crops {
            let (piece, confidence) = await classifier.classify(crop)
            classes[crop.square] = confidence >= DetectionSettings.classifierConfidence ? piece : .empty
        }
        return classes
    }

    func observation(
        from frame: CapturedFrame,
        classify: Bool,
        previousOccupancy: Occupancy
    ) async -> BoardObservation? {
        guard let quad = await detectQuad(in: frame) else { return nil }
        guard let warped = warp(frame, quad: quad) else { return nil }

        if detector != nil {
            return await observationFromDetector(
                frame: frame,
                quad: quad,
                warped: warped,
                previousOccupancy: previousOccupancy
            )
        }

        let crops = GridSampler.crops(from: warped.squareImage, orientation: orientation)

        if needsFingerprintSnapshot {
            occupancyEstimator.snapshot(crops: crops)
            needsFingerprintSnapshot = false
        }

        var classes: [ChessSquare: PieceClass] = [:]
        if classify, classifier != nil {
            classes = await classifySquares(from: warped.squareImage)
        }

        let occupancy: Occupancy
        let changedSquareCount: Int
        if occupancyEstimator.hasSnapshot {
            let change = occupancyEstimator.applyChanges(
                crops: crops,
                previous: previousOccupancy
            )
            occupancy = change.occupancy
            changedSquareCount = change.changedCount
        } else if classify, !classes.isEmpty {
            occupancy = occupancyEstimator.occupancy(crops: crops, classes: classes)
            changedSquareCount = 0
        } else {
            occupancy = occupancyEstimator.occupancy(crops: crops, classes: nil)
            changedSquareCount = 0
        }

        return BoardObservation(
            timestamp: frame.timestamp,
            quad: quad,
            occupancy: occupancy,
            classes: classes,
            changedSquareCount: changedSquareCount,
            warpedImage: warped.squareImage
        )
    }

    private func observationFromDetector(
        frame: CapturedFrame,
        quad: Quadrilateral,
        warped: WarpedBoard,
        previousOccupancy: Occupancy
    ) async -> BoardObservation {
        let bufferSize = CGSize(
            width: CVPixelBufferGetWidth(frame.buffer),
            height: CVPixelBufferGetHeight(frame.buffer)
        )
        let margin: CGFloat = 0.06
        let padded = quad.detectionPadding(fitting: margin, in: bufferSize)
        let detectWarp = padded.margin == 0
            ? warped
            : (warp(frame, quad: padded.quad) ?? warped)
        let usedMargin: CGFloat = detectWarp.quad == padded.quad ? padded.margin : 0
        let image = detectWarp.squareImage
        let boxes = await detector?.detectBoxes(in: image) ?? []
        let paddedSize = CGFloat(min(image.width, image.height))
        let overlayBoxes = Array(boxes.prefix(PieceDetection.maxOverlayBoxes))
        let yoloBases = PieceDetection.bases(
            from: boxes,
            paddedImageSize: paddedSize,
            margin: usedMargin
        )
        let yoloBoxes = PieceDetection.overlayBoxes(
            from: overlayBoxes,
            paddedImageSize: paddedSize,
            margin: usedMargin
        )
        let rawYoloOccupancy = PieceDetection.occupancy(
            from: boxes,
            paddedImageSize: paddedSize,
            margin: usedMargin,
            orientation: orientation,
            grid: refinedGrid
        )
        let yoloOccupancy = yoloOccupancySmoother.ingest(rawYoloOccupancy)
        let classes = PieceDetection.classes(
            from: boxes,
            paddedImageSize: paddedSize,
            margin: usedMargin,
            orientation: orientation,
            grid: refinedGrid
        )

        let crops = GridSampler.crops(from: warped.squareImage, orientation: orientation)
        if needsFingerprintSnapshot {
            occupancyEstimator.snapshot(crops: crops)
            needsFingerprintSnapshot = false
        }

        let occupancy: Occupancy
        let fingerprintChangedCount: Int
        if occupancyEstimator.hasSnapshot {
            let change = occupancyEstimator.applyChanges(
                crops: crops,
                previous: previousOccupancy
            )
            fingerprintChangedCount = change.changedCount
            // High Δ = lighting/shadow chaos: ignore fingerprint, let YOLO lead.
            let fused: Occupancy
            if OccupancyNoiseGate.fingerprintUnusable(changedCount: fingerprintChangedCount) {
                fused = yoloOccupancy
            } else {
                fused = OccupancyFusion.combine(
                    previous: previousOccupancy,
                    yolo: yoloOccupancy,
                    fingerprint: change.occupancy,
                    changed: change.changed
                )
            }
            let fusedHamming = previousOccupancy.hammingDistance(to: fused)
            if OccupancyNoiseGate.shouldFreeze(fusedHamming: fusedHamming) {
                occupancy = previousOccupancy
            } else {
                occupancy = fused
            }
        } else {
            fingerprintChangedCount = 0
            let fusedHamming = previousOccupancy.hammingDistance(to: yoloOccupancy)
            if OccupancyNoiseGate.shouldFreeze(fusedHamming: fusedHamming) {
                occupancy = previousOccupancy
            } else {
                occupancy = yoloOccupancy
            }
        }

        return BoardObservation(
            timestamp: frame.timestamp,
            quad: quad,
            occupancy: occupancy,
            classes: classes,
            changedSquareCount: fingerprintChangedCount,
            yoloBases: yoloBases,
            yoloBoxes: yoloBoxes,
            warpedImage: warped.squareImage
        )
    }

    func crops(from warped: CGImage) -> [SquareCrop] {
        GridSampler.crops(from: warped, orientation: orientation)
    }
}
