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
