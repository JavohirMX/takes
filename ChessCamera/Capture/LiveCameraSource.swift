import AVFoundation
import CoreMedia
import Foundation
import UIKit

final class LiveCameraSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.chesscamera.camera.session")
    private let outputQueue = DispatchQueue(label: "app.chesscamera.camera.frames")
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    private var output: AVCaptureVideoDataOutput?
    private var configured = false

    lazy var frames: AsyncStream<CapturedFrame> = {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                // Do not stop the capture session here. Cancelling the frame
                // consumer must not kill the live preview.
                self?.continuation = nil
            }
        }
    }()

    func start() async throws {
        let allowed = await Self.ensureAuthorized()
        guard allowed else { throw CaptureError.permissionDenied }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    if !self.captureSession.isRunning {
                        self.captureSession.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func pause() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.stopRunning()
                continuation.resume()
            }
        }
    }

    func updateVideoRotation(interfaceOrientation: UIInterfaceOrientation) {
        sessionQueue.async {
            let angle = Self.rotationAngle(forInterfaceOrientation: interfaceOrientation)
            if let connection = self.output?.connection(with: .video) {
                Self.applyRotation(angle, to: connection)
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        continuation?.yield(
            CapturedFrame(buffer: buffer, timestamp: ContinuousClock().now)
        )
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard let device = Self.preferredBackCamera() else {
            throw CaptureError.cameraUnavailable
        }

        // Prefer 720p; some multi-cam configs reject the preset — fall back to inputPriority.
        if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
        } else {
            captureSession.sessionPreset = .inputPriority
            Self.selectPrefer720pFormat(on: device)
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw CaptureError.cameraUnavailable
        }
        captureSession.addInput(input)

        Self.applyWideEquivalentZoom(on: device)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard captureSession.canAddOutput(output) else {
            throw CaptureError.cameraUnavailable
        }
        captureSession.addOutput(output)
        self.output = output

        if let connection = output.connection(with: .video) {
            Self.applyRotation(90, to: connection)
        }

        configured = true
    }

    /// Prefer virtual multi-cam (FOV headroom), then ultra-wide, then wide.
    /// Zoom is set separately to ~1.0× so the board fills more of the frame.
    private static func preferredBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInUltraWideCamera,
            .builtInWideAngleCamera
        ]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    /// Target wide-equivalent (~1.0×) zoom so board detection sees a larger board,
    /// while still using multi-cam / ultra-wide hardware for FOV headroom.
    private static func applyWideEquivalentZoom(on device: AVCaptureDevice) {
        let target = min(
            max(1.0, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor
        )
        guard abs(device.videoZoomFactor - target) > 0.01 else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = target
            device.unlockForConfiguration()
        } catch {
            // Leave default zoom if lock fails.
        }
    }

    private static func selectPrefer720pFormat(on device: AVCaptureDevice) {
        let preferred = device.formats
            .filter { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dims.width >= 1280 && dims.height >= 720
            }
            .sorted { a, b in
                let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                return (da.width * da.height) < (db.width * db.height)
            }
            .first
        guard let preferred else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = preferred
            device.unlockForConfiguration()
        } catch {
            // Keep whatever the session chose.
        }
    }

    private func stopRunning() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        continuation?.finish()
        continuation = nil
    }

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func ensureAuthorized() async -> Bool {
        switch authorizationStatus() {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
        }
    }

    static func applyRotation(_ angle: CGFloat, to connection: AVCaptureConnection) {
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    static func rotationAngle(for orientation: AVCaptureVideoOrientation) -> CGFloat {
        // Degrees clockwise from sensor-native landscapeRight (0°).
        switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeRight: 0
        case .landscapeLeft: 180
        @unknown default: 90
        }
    }

    /// Preferred path: map interface orientation → angle (avoids UIDevice/AVCapture landscape name confusion).
    static func rotationAngle(forInterfaceOrientation orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 180
        case .landscapeRight: 0
        default: 90
        }
    }
}
