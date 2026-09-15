import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import ChessCamera

@Test func checkerboardScoresHigherThanFlat() throws {
    let board = try makeCheckerboard(size: 128, phase: 0)
    let flat = try makeFlat(size: 128, gray: 128)
    let boardScore = ChessboardGridScore.score(cgImage: board)
    let flatScore = ChessboardGridScore.score(cgImage: flat)
    #expect(boardScore > 0.35)
    #expect(flatScore < 0.15)
    #expect(boardScore > flatScore * 2)
}

@Test func occupiedCheckerboardStillBeatsFlat() throws {
    let board = try makeCheckerboard(size: 128, phase: 0, occludeCells: 20)
    let flat = try makeFlat(size: 128, gray: 110)
    let noise = try makeNoise(size: 128)
    let boardScore = ChessboardGridScore.score(cgImage: board)
    let flatScore = ChessboardGridScore.score(cgImage: flat)
    let noiseScore = ChessboardGridScore.score(cgImage: noise)
    #expect(boardScore > flatScore)
    #expect(boardScore > noiseScore)
}

@Test func oppositeCheckerboardPhaseAlsoScores() throws {
    let phase0 = try makeCheckerboard(size: 128, phase: 0)
    let phase1 = try makeCheckerboard(size: 128, phase: 1)
    let s0 = ChessboardGridScore.score(cgImage: phase0)
    let s1 = ChessboardGridScore.score(cgImage: phase1)
    #expect(s0 > 0.3)
    #expect(s1 > 0.3)
}

@Test func quadConsensusRequiresSimilarHits() {
    var consensus = QuadConsensus(needed: 3, similarityFraction: 0.1)
    let size = CGSize(width: 1000, height: 1000)
    let base = Quadrilateral(
        topLeft: CGPoint(x: 100, y: 100),
        topRight: CGPoint(x: 900, y: 100),
        bottomRight: CGPoint(x: 900, y: 900),
        bottomLeft: CGPoint(x: 100, y: 900)
    )
    for i in 0..<2 {
        let jittered = base.blended(
            with: Quadrilateral(
                topLeft: CGPoint(x: 100 + CGFloat(i), y: 100),
                topRight: CGPoint(x: 900, y: 100),
                bottomRight: CGPoint(x: 900, y: 900),
                bottomLeft: CGPoint(x: 100, y: 900)
            ),
            t: 0
        )
        #expect(consensus.ingest(jittered, imageSize: size) == nil)
    }
    let accepted = consensus.ingest(base, imageSize: size)
    #expect(accepted != nil)
    #expect(accepted?.topLeft.x ?? 0 > 99)
}

@Test func quadConsensusResetsOnJump() {
    var consensus = QuadConsensus(needed: 3, similarityFraction: 0.05)
    let size = CGSize(width: 1000, height: 1000)
    let a = Quadrilateral(
        topLeft: CGPoint(x: 100, y: 100),
        topRight: CGPoint(x: 400, y: 100),
        bottomRight: CGPoint(x: 400, y: 400),
        bottomLeft: CGPoint(x: 100, y: 400)
    )
    let b = Quadrilateral(
        topLeft: CGPoint(x: 600, y: 600),
        topRight: CGPoint(x: 900, y: 600),
        bottomRight: CGPoint(x: 900, y: 900),
        bottomLeft: CGPoint(x: 600, y: 900)
    )
    #expect(consensus.ingest(a, imageSize: size) == nil)
    #expect(consensus.ingest(a, imageSize: size) == nil)
    #expect(consensus.ingest(b, imageSize: size) == nil)
    #expect(consensus.count == 1)
    #expect(consensus.ingest(b, imageSize: size) == nil)
    let accepted = consensus.ingest(b, imageSize: size)
    #expect(accepted != nil)
}

@Test func lockedPipelineIgnoresNewDetections() async throws {
    let locked = Quadrilateral(
        topLeft: CGPoint(x: 10, y: 10),
        topRight: CGPoint(x: 100, y: 10),
        bottomRight: CGPoint(x: 100, y: 100),
        bottomLeft: CGPoint(x: 10, y: 100)
    )
    let other = Quadrilateral(
        topLeft: CGPoint(x: 200, y: 200),
        topRight: CGPoint(x: 400, y: 200),
        bottomRight: CGPoint(x: 400, y: 400),
        bottomLeft: CGPoint(x: 200, y: 400)
    )
    let localizer = StubLocalizer(quad: other)
    let pipeline = VisionPipeline(localizer: localizer, classifier: nil, detector: nil)
    await pipeline.setLockedQuad(locked)
    let buffer = try makeBGRAPixelBuffer(width: 64, height: 64, gray: 80)
    let frame = CapturedFrame(buffer: buffer, timestamp: ContinuousClock().now)
    let result = await pipeline.detectQuad(in: frame)
    #expect(result == locked)
}

@Test func classifySquaresDoesNotCallDetector() async throws {
    let detector = CountingDetector()
    let pipeline = VisionPipeline(
        localizer: StubLocalizer(quad: nil),
        classifier: nil,
        detector: detector
    )
    let image = try makeFlat(size: 64, gray: 128)
    let classes = await pipeline.classifySquares(from: image)
    #expect(classes.isEmpty)
    #expect(detector.detectCount == 0)
}

@Test func liveObservationUsesWarpedBoxesNotClassMap() async throws {
    let detector = CountingDetector()
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 256, y: 0),
        bottomRight: CGPoint(x: 256, y: 256),
        bottomLeft: CGPoint(x: 0, y: 256)
    )
    let pipeline = VisionPipeline(
        localizer: StubLocalizer(quad: quad),
        classifier: nil,
        detector: detector
    )
    await pipeline.setLockedQuad(quad)
    let buffer = try makeBGRAPixelBuffer(width: 256, height: 256, gray: 90)
    let frame = CapturedFrame(buffer: buffer, timestamp: ContinuousClock().now)
    let observation = await pipeline.observation(
        from: frame,
        classify: false,
        previousOccupancy: Occupancy.standardStart()
    )
    #expect(observation != nil)
    #expect(detector.detectCount == 0)
    #expect(detector.boxesCount == 1)
    #expect(observation?.occupancy.occupied(ChessSquare(file: 4, rank: 0)) == true)
    #expect(observation?.classes[ChessSquare(file: 4, rank: 0)] == .whiteKing)
    #expect(observation?.yoloBases.count == 1)
    if let uv = observation?.yoloBases.first {
        #expect(abs(uv.x - 288.0 / 512.0) < 0.002)
        #expect(abs(uv.y - 480.0 / 512.0) < 0.002)
    }
}

private final class CountingDetector: PieceDetector, @unchecked Sendable {
    var detectCount = 0
    var boxesCount = 0

    func detect(in warped: CGImage, orientation: BoardOrientation) async -> [ChessSquare: PieceClass] {
        detectCount += 1
        return [ChessSquare(file: 4, rank: 0): .whiteKing]
    }

    func detectBoxes(in image: CGImage) async -> [PieceDetection.Box] {
        boxesCount += 1
        return [
            PieceDetection.Box(
                id: 0,
                piece: .whiteKing,
                confidence: 0.9,
                bufferRect: CGRect(x: 256, y: 448, width: 64, height: 64)
            )
        ]
    }
}

private struct StubLocalizer: BoardLocalizer {
    var quad: Quadrilateral?
    func detect(in buffer: CVPixelBuffer) async -> Quadrilateral? { quad }
}

private func makeCheckerboard(size: Int, phase: Int, occludeCells: Int = 0) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    let cell = size / 8
    for y in 0..<size {
        for x in 0..<size {
            let file = x / max(cell, 1)
            let rank = y / max(cell, 1)
            let dark = ((file + rank) % 2) == phase
            let v: UInt8 = dark ? 40 : 210
            let i = (y * size + x) * 4
            bytes[i] = v
            bytes[i + 1] = v
            bytes[i + 2] = v
            bytes[i + 3] = 255
        }
    }
    if occludeCells > 0 {
        var occluded = 0
        for rank in 0..<8 where occluded < occludeCells {
            for file in 0..<8 where occluded < occludeCells {
                if (file + rank) % 3 != 0 { continue }
                let cx = file * cell + cell / 2
                let cy = rank * cell + cell / 2
                for dy in -cell / 3...cell / 3 {
                    for dx in -cell / 3...cell / 3 {
                        let x = cx + dx
                        let y = cy + dy
                        guard x >= 0, y >= 0, x < size, y < size else { continue }
                        let i = (y * size + x) * 4
                        bytes[i] = 120
                        bytes[i + 1] = 90
                        bytes[i + 2] = 70
                        bytes[i + 3] = 255
                    }
                }
                occluded += 1
            }
        }
    }
    return try cgImage(from: bytes, size: size)
}

private func makeFlat(size: Int, gray: UInt8) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) {
        let o = i * 4
        bytes[o] = gray
        bytes[o + 1] = gray
        bytes[o + 2] = gray
        bytes[o + 3] = 255
    }
    return try cgImage(from: bytes, size: size)
}

private func makeNoise(size: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    var state: UInt64 = 42
    for i in 0..<(size * size) {
        state = state &* 6364136223846793005 &+ 1
        let v = UInt8(truncatingIfNeeded: state >> 56)
        let o = i * 4
        bytes[o] = v
        bytes[o + 1] = v
        bytes[o + 2] = v
        bytes[o + 3] = 255
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

private func makeBGRAPixelBuffer(width: Int, height: Int, gray: UInt8) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ] as CFDictionary,
        &buffer
    )
    guard status == kCVReturnSuccess, let buffer else {
        struct BufferError: Error {}
        throw BufferError()
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
        struct BufferError: Error {}
        throw BufferError()
    }
    let ptr = base.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let i = y * bytesPerRow + x * 4
            ptr[i] = gray
            ptr[i + 1] = gray
            ptr[i + 2] = gray
            ptr[i + 3] = 255
        }
    }
    return buffer
}
