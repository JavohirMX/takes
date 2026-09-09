import CoreGraphics
import CoreVideo
import Foundation

struct BoardObservation: Sendable {
    var timestamp: ContinuousClock.Instant
    var quad: Quadrilateral
    var occupancy: Occupancy
    var classes: [ChessSquare: PieceClass]
    nonisolated(unsafe) var warpedImage: CGImage?
}

actor VisionPipeline {
    var lockedQuad: Quadrilateral?
    var orientation: BoardOrientation = .whiteAtBottom
    var occupancyEstimator = HeuristicOccupancyEstimator()

    private let localizer: any BoardLocalizer
    private let classifier: (any PieceClassifier)?

    init(
        localizer: any BoardLocalizer = VisionBoardLocalizer(),
        classifier: (any PieceClassifier)? = CoreMLPieceClassifier.loadBundled()
    ) {
        self.localizer = localizer
        self.classifier = classifier
    }

    var hasClassifier: Bool { classifier != nil }

    func setLockedQuad(_ quad: Quadrilateral?) {
        lockedQuad = quad
    }

    func setOrientation(_ orientation: BoardOrientation) {
        self.orientation = orientation
    }

    func captureEmptyBaselines(from warped: CGImage, occupied: Occupancy) {
        let crops = GridSampler.crops(from: warped, orientation: orientation)
        occupancyEstimator.captureBaselines(crops: crops, occupied: occupied)
    }

    func detectQuad(in frame: CapturedFrame) async -> Quadrilateral? {
        if let lockedQuad { return lockedQuad }
        return await localizer.detect(in: frame.buffer)
    }

    func warp(_ frame: CapturedFrame, quad: Quadrilateral) -> WarpedBoard? {
        BoardWarper.warp(frame.buffer, quad: quad, size: 512)
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
        classify: Bool
    ) async -> BoardObservation? {
        guard let quad = await detectQuad(in: frame) else { return nil }
        guard let warped = warp(frame, quad: quad) else { return nil }
        let crops = GridSampler.crops(from: warped.squareImage, orientation: orientation)
        var classes: [ChessSquare: PieceClass] = [:]
        if classify, classifier != nil {
            classes = await classifySquares(from: warped.squareImage)
        }
        let occupancy = occupancyEstimator.occupancy(
            crops: crops,
            classes: classify ? classes : nil
        )
        return BoardObservation(
            timestamp: frame.timestamp,
            quad: quad,
            occupancy: occupancy,
            classes: classes,
            warpedImage: warped.squareImage
        )
    }

    func crops(from warped: CGImage) -> [SquareCrop] {
        GridSampler.crops(from: warped, orientation: orientation)
    }
}
