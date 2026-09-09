import AVFoundation
import Foundation

final class AssetVideoSource: FrameSource, @unchecked Sendable {
    private let url: URL
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    private var readerTask: Task<Void, Never>?
    private var reader: AVAssetReader?

    init(url: URL) {
        self.url = url
    }

    lazy var frames: AsyncStream<CapturedFrame> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()

    func start() async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw CaptureError.noVideoTrack }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw CaptureError.readFailed }
        reader.add(output)
        guard reader.startReading() else { throw CaptureError.readFailed }
        self.reader = reader

        let t0 = ContinuousClock().now
        let stream = continuation
        readerTask = Task.detached(priority: .userInitiated) {
            var lastEmitted = -1.0
            while reader.status == .reading, !Task.isCancelled {
                guard let sample = output.copyNextSampleBuffer() else { break }
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                if pts.isFinite, lastEmitted >= 0, (pts - lastEmitted) < 0.1 {
                    continue
                }
                if pts.isFinite {
                    lastEmitted = pts
                }
                let timestamp: ContinuousClock.Instant
                if pts.isFinite, pts >= 0 {
                    timestamp = t0.advanced(by: .seconds(pts))
                } else {
                    timestamp = ContinuousClock().now
                }
                stream?.yield(CapturedFrame(buffer: buffer, timestamp: timestamp))
            }
            stream?.finish()
        }
    }

    func stop() async {
        readerTask?.cancel()
        readerTask = nil
        reader?.cancelReading()
        reader = nil
        continuation?.finish()
        continuation = nil
    }
}
