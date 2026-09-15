import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import ChessCamera

@Test func paddedRefinerReturnsNilOnFlatGray() throws {
    let buffer = try makeGrayPixelBuffer(width: 320, height: 240, gray: 180)
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 40, y: 30),
        topRight: CGPoint(x: 280, y: 30),
        bottomRight: CGPoint(x: 280, y: 210),
        bottomLeft: CGPoint(x: 40, y: 210)
    )
    #expect(
        PaddedBoardRefiner.refine(
            quad: quad,
            buffer: buffer,
            bufferSize: CGSize(width: 320, height: 240)
        ) == nil
    )
}

@Test func scoreGateAcceptsImprovedChessboardSnap() {
    #expect(
        PaddedBoardRefiner.passesScoreGate(
            seedScore: 0.4,
            snappedScore: 0.55,
            source: .chessboardCorners
        )
    )
}

@Test func scoreGateAllowsSmallDropWithinEpsilon() {
    #expect(
        PaddedBoardRefiner.passesScoreGate(
            seedScore: 0.5,
            snappedScore: 0.46,
            source: .chessboardCorners
        )
    )
}

@Test func scoreGateRejectsWorsenedSnap() {
    #expect(
        !PaddedBoardRefiner.passesScoreGate(
            seedScore: 0.6,
            snappedScore: 0.4,
            source: .chessboardCorners
        )
    )
}

@Test func scoreGateRejectsBelowFloor() {
    #expect(
        !PaddedBoardRefiner.passesScoreGate(
            seedScore: 0.05,
            snappedScore: 0.15,
            source: .chessboardCorners
        )
    )
}

@Test func houghScoreGateIsStricterThanChessboard() {
    #expect(
        PaddedBoardRefiner.passesScoreGate(
            seedScore: 0.3,
            snappedScore: 0.32,
            source: .chessboardCorners
        )
    )
    #expect(
        !PaddedBoardRefiner.passesScoreGate(
            seedScore: 0.3,
            snappedScore: 0.32,
            source: .hough
        )
    )
    #expect(
        PaddedBoardRefiner.passesScoreGate(
            seedScore: 0.3,
            snappedScore: 0.4,
            source: .hough
        )
    )
}

@Test func stableSnapSettlesAfterTwoSimilarHits() {
    let size = CGSize(width: 1000, height: 1000)
    let a = Quadrilateral(
        topLeft: CGPoint(x: 100, y: 100),
        topRight: CGPoint(x: 900, y: 100),
        bottomRight: CGPoint(x: 900, y: 900),
        bottomLeft: CGPoint(x: 100, y: 900)
    )
    let first = BoardStudioRefinePolicy.ingestStableSnap(
        pending: nil,
        hits: 0,
        candidate: a,
        imageSize: size
    )
    #expect(first.hits == 1)
    #expect(!first.settled)

    let second = BoardStudioRefinePolicy.ingestStableSnap(
        pending: first.pending,
        hits: first.hits,
        candidate: a,
        imageSize: size
    )
    #expect(second.hits == 2)
    #expect(second.settled)
}

@Test func stableSnapResetsOnJump() {
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
    let first = BoardStudioRefinePolicy.ingestStableSnap(
        pending: nil,
        hits: 0,
        candidate: a,
        imageSize: size
    )
    let jumped = BoardStudioRefinePolicy.ingestStableSnap(
        pending: first.pending,
        hits: first.hits,
        candidate: b,
        imageSize: size
    )
    #expect(jumped.hits == 1)
    #expect(!jumped.settled)
    #expect(jumped.pending == b)
}

@Test func templateRecaptureOnlyWhenSnapMoves() {
    let size = CGSize(width: 1000, height: 1000)
    let a = Quadrilateral(
        topLeft: CGPoint(x: 100, y: 100),
        topRight: CGPoint(x: 900, y: 100),
        bottomRight: CGPoint(x: 900, y: 900),
        bottomLeft: CGPoint(x: 100, y: 900)
    )
    let nearby = Quadrilateral(
        topLeft: CGPoint(x: 105, y: 100),
        topRight: CGPoint(x: 900, y: 100),
        bottomRight: CGPoint(x: 900, y: 900),
        bottomLeft: CGPoint(x: 100, y: 900)
    )
    let far = Quadrilateral(
        topLeft: CGPoint(x: 300, y: 300),
        topRight: CGPoint(x: 700, y: 300),
        bottomRight: CGPoint(x: 700, y: 700),
        bottomLeft: CGPoint(x: 300, y: 700)
    )
    #expect(!BoardStudioRefinePolicy.shouldRecaptureTemplates(previous: a, snapped: nearby, imageSize: size))
    #expect(BoardStudioRefinePolicy.shouldRecaptureTemplates(previous: a, snapped: far, imageSize: size))
    #expect(BoardStudioRefinePolicy.shouldRecaptureTemplates(previous: nil, snapped: a, imageSize: size))
}

@Test func weakTrackRecoversAfterDuration() {
    let start = ContinuousClock.now
    #expect(
        BoardStudioRefinePolicy.weakTrackAction(
            weakFrames: 1,
            weakStartedAt: start,
            now: start
        ) == .updateQuad
    )
    #expect(
        BoardStudioRefinePolicy.weakTrackAction(
            weakFrames: 3,
            weakStartedAt: start,
            now: start
        ) == .freeze
    )
    #expect(
        BoardStudioRefinePolicy.weakTrackAction(
            weakFrames: 5,
            weakStartedAt: start,
            now: start.advanced(by: .seconds(1))
        ) == .restartVision
    )
}

@Test func quadConsensusDefaultNeedsThreeHits() {
    var consensus = QuadConsensus()
    let size = CGSize(width: 1000, height: 1000)
    let base = Quadrilateral(
        topLeft: CGPoint(x: 100, y: 100),
        topRight: CGPoint(x: 900, y: 100),
        bottomRight: CGPoint(x: 900, y: 900),
        bottomLeft: CGPoint(x: 100, y: 900)
    )
    #expect(consensus.ingest(base, imageSize: size) == nil)
    #expect(consensus.ingest(base, imageSize: size) == nil)
    #expect(consensus.ingest(base, imageSize: size) != nil)
}

private func makeGrayPixelBuffer(width: Int, height: Int, gray: UInt8) throws -> CVPixelBuffer {
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
