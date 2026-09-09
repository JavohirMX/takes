import CoreVideo
import Foundation

struct CapturedFrame: Sendable {
    nonisolated(unsafe) let buffer: CVPixelBuffer
    let timestamp: ContinuousClock.Instant
}

protocol FrameSource: Sendable {
    var frames: AsyncStream<CapturedFrame> { get }
    func start() async throws
    func stop() async
}

enum CaptureError: Error, Equatable, LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case noVideoTrack
    case readFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "Camera unavailable on this device."
        case .permissionDenied:
            "Camera access is turned off."
        case .noVideoTrack:
            "That video has no picture track."
        case .readFailed:
            "Couldn’t read the video. Retry or pick another clip."
        }
    }
}
