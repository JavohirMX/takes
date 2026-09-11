import ChessKit
import CoreGraphics
import Foundation
import Testing
@testable import ChessCamera

@Test func uniformSquareIsEmptyWithoutBaseline() throws {
    let image = try makeGrayImage(size: 64, value: 128)
    let fingerprint = SquareFingerprint.make(image)
    #expect(!OccupancyHeuristic.isOccupied(fingerprint: fingerprint, baseline: nil))
}

@Test func checkerboardSquareIsOccupiedWithoutBaseline() throws {
    let image = try makeCheckerImage(size: 64)
    let fingerprint = SquareFingerprint.make(image)
    #expect(OccupancyHeuristic.isOccupied(fingerprint: fingerprint, baseline: nil))
}

@Test func occupancyUsesClassMapWhenProvided() throws {
    let gray = try makeGrayImage(size: 32, value: 200)
    let crops = [
        SquareCrop(square: ChessSquare.parse("e4")!, image: gray),
        SquareCrop(square: ChessSquare.parse("e5")!, image: gray)
    ]
    let estimator = HeuristicOccupancyEstimator()
    let occupancy = estimator.occupancy(
        crops: crops,
        classes: [
            ChessSquare.parse("e4")!: .whitePawn,
            ChessSquare.parse("e5")!: .empty
        ]
    )
    #expect(occupancy.occupied(ChessSquare.parse("e4")!))
    #expect(!occupancy.occupied(ChessSquare.parse("e5")!))
}

@Test func fenCodecStandardIsLegal() {
    #expect(FenCodec.isLegal(FenCodec.standard))
    #expect(FenCodec.isStandardStart(FenCodec.standard))
}

@Test func fenCodecRoundTripsPlacement() {
    let classes = FenCodec.standardClasses()
    let fen = FenCodec.fen(from: classes)
    #expect(FenCodec.isStandardStart(fen))
    #expect(FenCodec.parsePieces(fen)[ChessSquare.parse("e1")!] == .whiteKing)
}

@Test func pgnMoveListExtractsSans() {
    let sans = PGNMoveList.sans(from: "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0")
    #expect(sans == ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"])
}

@Test func pgnPreviewShowsFirstSixPlies() {
    let preview = PGNMoveList.preview("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Bxc6", maxPlies: 6)
    #expect(preview == "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6")
}

@Test func gridSamplerExportsSixtyFourCrops() throws {
    let image = try makeGrayImage(size: 512, value: 90)
    let crops = GridSampler.crops(from: image, orientation: .whiteAtBottom, inset: 0)
    #expect(crops.count == 64)
    #expect(crops.first?.square.algebraic == "a8")
    #expect(crops.last?.square.algebraic == "h1")
}

@Test func changeDetectorIgnoresGlobalLightingShift() {
    let scores = [Double](repeating: 6, count: 64)
    let changed = SquareChangeDetector.changedMask(scores: scores)
    #expect(!changed.contains(true))
}

@Test func changeDetectorFlagsTwoOutlierSquares() {
    var scores = [Double](repeating: 4, count: 64)
    scores[12] = 48
    scores[20] = 52
    let changed = SquareChangeDetector.changedMask(scores: scores)
    #expect(changed.filter { $0 }.count == 2)
    #expect(changed[12])
    #expect(changed[20])
}

@Test func changeDetectorFlagsMarginalQuietMoveScores() {
    var scores = [Double](repeating: 3, count: 64)
    scores[12] = 11
    scores[20] = 12
    let changed = SquareChangeDetector.changedMask(scores: scores)
    #expect(changed[12])
    #expect(changed[20])
    #expect(changed.filter { $0 }.count == 2)
}

@Test func occupancyAppliesQuietMoveFromSnapshot() throws {
    let empty = try makeGrayImage(size: 32, value: 200)
    let busy = try makeCheckerImage(size: 32)
    let e2 = ChessSquare.parse("e2")!
    let e4 = ChessSquare.parse("e4")!
    var before: [SquareCrop] = []
    var after: [SquareCrop] = []
    for file in 0..<8 {
        for rank in 0..<8 {
            let square = ChessSquare(file: file, rank: rank)
            let startImage = square == e2 ? busy : empty
            let nextImage = square == e4 ? busy : empty
            before.append(SquareCrop(square: square, image: startImage))
            after.append(SquareCrop(square: square, image: nextImage))
        }
    }
    var estimator = HeuristicOccupancyEstimator()
    estimator.snapshot(crops: before)
    var previous = Occupancy()
    previous.set(e2, occupied: true)
    let change = estimator.applyChanges(crops: after, previous: previous)
    #expect(change.changedCount == 2)
    #expect(!change.occupancy.occupied(e2))
    #expect(change.occupancy.occupied(e4))
}

@Test func emptiedUsesSoftVarianceRatio() {
    var estimator = HeuristicOccupancyEstimator()
    estimator.emptiedVarianceRatio = 0.75
    let previous = SquareFingerprint(mean: 100, variance: 100)
    let emptied = SquareFingerprint(mean: 100, variance: 70)
    let stillBusy = SquareFingerprint(mean: 100, variance: 90)
    let square = ChessSquare.parse("e2")!
    #expect(estimator.isEmptied(current: emptied, previous: previous, square: square))
    #expect(!estimator.isEmptied(current: stillBusy, previous: previous, square: square))
}

@Test func emptiedPrefersEmptyBaselineProximity() {
    var estimator = HeuristicOccupancyEstimator()
    let square = ChessSquare.parse("e2")!
    let emptyLook = SquareFingerprint(mean: 180, variance: 20)
    estimator.emptyBaseline[square] = emptyLook
    let previousPiece = SquareFingerprint(mean: 90, variance: 120)
    let afterLeave = SquareFingerprint(mean: 175, variance: 110)
    #expect(estimator.isEmptied(current: afterLeave, previous: previousPiece, square: square))
}

@Test func quietMoveE2E4MatchesInferrer() throws {
    let empty = try makeGrayImage(size: 32, value: 200)
    let busy = try makeCheckerImage(size: 32)
    let e2 = ChessSquare.parse("e2")!
    let e4 = ChessSquare.parse("e4")!

    var before: [SquareCrop] = []
    var after: [SquareCrop] = []
    let startOcc = Occupancy.standardStart()
    for file in 0..<8 {
        for rank in 0..<8 {
            let square = ChessSquare(file: file, rank: rank)
            let occupied = startOcc.occupied(square)
            before.append(SquareCrop(square: square, image: occupied ? busy : empty))
            var nextOccupied = occupied
            if square == e2 { nextOccupied = false }
            if square == e4 { nextOccupied = true }
            after.append(SquareCrop(square: square, image: nextOccupied ? busy : empty))
        }
    }

    var estimator = HeuristicOccupancyEstimator()
    estimator.snapshot(crops: before)
    let change = estimator.applyChanges(crops: after, previous: startOcc)
    #expect(!change.occupancy.occupied(e2))
    #expect(change.occupancy.occupied(e4))
    #expect(startOcc.hammingDistance(to: change.occupancy) == 2)

    var settle = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock().now
    _ = settle.ingest(startOcc, at: t0)
    _ = settle.ingest(change.occupancy, at: t0.advanced(by: .milliseconds(50)))
    let motion = settle.ingest(change.occupancy, at: t0.advanced(by: .milliseconds(700)))
    guard case .stable(let settled) = motion else {
        Issue.record("expected settled occupancy after quiet move")
        return
    }

    let inference = MoveInferrer.infer(
        delta: VisualDelta(previous: startOcc, current: settled, observedClasses: [:]),
        board: Board()
    )
    guard case .unique(let move) = inference else {
        Issue.record("expected unique e4, got \(inference)")
        return
    }
    #expect(move.san == "e4")
}

@Test func captureAndCastleThroughChangePipeline() throws {
    let empty = try makeGrayImage(size: 32, value: 200)
    let busy = try makeCheckerImage(size: 32)

    // Capture Bxc6: only origin clears (destination stays occupied).
    let captureEngine = try GameEngine(fen: "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3")
    let captureBefore = captureEngine.occupancy()
    let b5 = ChessSquare.parse("b5")!
    let cropsBeforeCapture = makeBoardCrops(occupancy: captureBefore, empty: empty, busy: busy)
    var captureAfterOcc = captureBefore
    captureAfterOcc.set(b5, occupied: false)
    let cropsAfterCapture = makeBoardCrops(occupancy: captureAfterOcc, empty: empty, busy: busy)
    var captureEstimator = HeuristicOccupancyEstimator()
    captureEstimator.snapshot(crops: cropsBeforeCapture)
    let captureChange = captureEstimator.applyChanges(crops: cropsAfterCapture, previous: captureBefore)
    let captureInference = MoveInferrer.infer(
        delta: VisualDelta(previous: captureBefore, current: captureChange.occupancy, observedClasses: [:]),
        board: captureEngine.board
    )
    #expect(captureInference.san == Move(san: "Bxc6", position: captureEngine.board.position)?.san)

    // Castling O-O: four-square occupancy delta.
    let castleEngine = try GameEngine(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    let castleBefore = castleEngine.occupancy()
    var castleAfterOcc = castleBefore
    castleAfterOcc.set(ChessSquare.parse("e1")!, occupied: false)
    castleAfterOcc.set(ChessSquare.parse("h1")!, occupied: false)
    castleAfterOcc.set(ChessSquare.parse("g1")!, occupied: true)
    castleAfterOcc.set(ChessSquare.parse("f1")!, occupied: true)
    let cropsBeforeCastle = makeBoardCrops(occupancy: castleBefore, empty: empty, busy: busy)
    let cropsAfterCastle = makeBoardCrops(occupancy: castleAfterOcc, empty: empty, busy: busy)
    var castleEstimator = HeuristicOccupancyEstimator()
    castleEstimator.snapshot(crops: cropsBeforeCastle)
    let castleChange = castleEstimator.applyChanges(crops: cropsAfterCastle, previous: castleBefore)
    let castleInference = MoveInferrer.infer(
        delta: VisualDelta(previous: castleBefore, current: castleChange.occupancy, observedClasses: [:]),
        board: castleEngine.board
    )
    #expect(castleInference.san == Move(san: "O-O", position: castleEngine.board.position)?.san)
}

@Test func quadrilateralSimilarityAndBlend() {
    let a = Quadrilateral(
        topLeft: CGPoint(x: 10, y: 10),
        topRight: CGPoint(x: 100, y: 10),
        bottomRight: CGPoint(x: 100, y: 100),
        bottomLeft: CGPoint(x: 10, y: 100)
    )
    let b = Quadrilateral(
        topLeft: CGPoint(x: 14, y: 12),
        topRight: CGPoint(x: 104, y: 11),
        bottomRight: CGPoint(x: 101, y: 103),
        bottomLeft: CGPoint(x: 12, y: 99)
    )
    let far = Quadrilateral(
        topLeft: CGPoint(x: 200, y: 200),
        topRight: CGPoint(x: 300, y: 200),
        bottomRight: CGPoint(x: 300, y: 300),
        bottomLeft: CGPoint(x: 200, y: 300)
    )
    let size = CGSize(width: 1280, height: 720)
    #expect(a.isSimilar(to: b, imageSize: size))
    #expect(!a.isSimilar(to: far, imageSize: size))
    let mixed = a.blended(with: b, t: 0.5)
    #expect(abs(mixed.topLeft.x - 12) < 0.01)
}

private func makeBoardCrops(occupancy: Occupancy, empty: CGImage, busy: CGImage) -> [SquareCrop] {
    var crops: [SquareCrop] = []
    for file in 0..<8 {
        for rank in 0..<8 {
            let square = ChessSquare(file: file, rank: rank)
            crops.append(SquareCrop(
                square: square,
                image: occupancy.occupied(square) ? busy : empty
            ))
        }
    }
    return crops
}

private func makeGrayImage(size: Int, value: UInt8) throws -> CGImage {
    let bytes = [UInt8](repeating: value, count: size * size * 4)
    return try cgImage(from: bytes, size: size)
}

private func makeCheckerImage(size: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let on = ((x / 4) + (y / 4)).isMultiple(of: 2)
            let v: UInt8 = on ? 255 : 0
            let i = (y * size + x) * 4
            bytes[i] = v
            bytes[i + 1] = v
            bytes[i + 2] = v
            bytes[i + 3] = 255
        }
    }
    return try cgImage(from: bytes, size: size)
}

private func cgImage(from bytes: [UInt8], size: Int) throws -> CGImage {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        struct ImageError: Error {}
        throw ImageError()
    }
    return image
}
