import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

struct BoardObservation: Sendable {
    var timestamp: ContinuousClock.Instant
    var quad: Quadrilateral
    var occupancy: Occupancy
    var classes: [ChessSquare: PieceClass]
    /// Squares the change detector flagged this frame (0 when using absolute/heuristic fallback).
    var changedSquareCount: Int
    nonisolated(unsafe) var warpedImage: CGImage?
}

actor VisionPipeline {
    var lockedQuad: Quadrilateral?
    var orientation: BoardOrientation = .whiteAtBottom
    var occupancyEstimator = HeuristicOccupancyEstimator()

    private let localizer: any BoardLocalizer
    private let classifier: (any PieceClassifier)?
    private let detector: (any PieceDetector)?
    private var needsFingerprintSnapshot = false
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false])

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
    }

    func setOrientation(_ orientation: BoardOrientation) {
        self.orientation = orientation
    }

    func requestFingerprintSnapshot() {
        needsFingerprintSnapshot = true
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
            classes[crop.square] = confidence >= 0.35 ? piece : .empty
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
        let occupancy: Occupancy
        if let image = cgImage(from: frame.buffer) {
            let boxes = await detectPieceBoxes(in: image)
            occupancy = PieceDetection.occupancy(
                from: boxes,
                quad: quad,
                orientation: orientation
            )
        } else {
            occupancy = Occupancy()
        }
        return BoardObservation(
            timestamp: frame.timestamp,
            quad: quad,
            occupancy: occupancy,
            classes: [:],
            changedSquareCount: previousOccupancy.hammingDistance(to: occupancy),
            warpedImage: warped.squareImage
        )
    }

    private func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        return imageContext.createCGImage(image, from: image.extent)
    }

    func crops(from warped: CGImage) -> [SquareCrop] {
        GridSampler.crops(from: warped, orientation: orientation)
    }
}
