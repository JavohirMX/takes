import AVFoundation
import Foundation

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
                guard let self else { return }
                self.sessionQueue.async {
                    self.stopRunning()
                }
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

    func updateVideoRotation(interfaceOrientation: AVCaptureVideoOrientation) {
        sessionQueue.async {
            let angle = Self.rotationAngle(for: interfaceOrientation)
            if let connection = self.output?.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
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
        captureSession.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            captureSession.commitConfiguration()
            throw CaptureError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw CaptureError.cameraUnavailable
        }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            throw CaptureError.cameraUnavailable
        }
        captureSession.addOutput(output)
        self.output = output

        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        captureSession.commitConfiguration()
        configured = true
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

    private static func rotationAngle(for orientation: AVCaptureVideoOrientation) -> CGFloat {
        switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeRight: 180
        case .landscapeLeft: 0
        @unknown default: 90
        }
    }
}
