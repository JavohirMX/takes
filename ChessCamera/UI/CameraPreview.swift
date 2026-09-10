import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    var session: AVCaptureSession?
    var stillImage: CGImage?
    /// Matches `LiveCameraSource` data-output rotation so overlays and preview share letterbox space.
    var videoRotationAngle: CGFloat = 90

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = session
        view.stillImage = stillImage
        view.videoRotationAngle = videoRotationAngle
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.session = session
        uiView.stillImage = stillImage
        uiView.videoRotationAngle = videoRotationAngle
    }
}

/// Apple's AVCam pattern: the preview layer *is* the view's backing layer.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private let imageView = UIImageView()

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set {
            if previewLayer.session !== newValue {
                previewLayer.session = newValue
            }
            applyRotation()
            applyStillImage()
        }
    }

    var stillImage: CGImage? {
        didSet { applyStillImage() }
    }

    var videoRotationAngle: CGFloat = 90 {
        didSet {
            guard abs(oldValue - videoRotationAngle) > 0.01 else { return }
            applyRotation()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = UIColor.black.cgColor

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.isHidden = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        applyRotation()
    }

    private func applyRotation() {
        guard let connection = previewLayer.connection else { return }
        LiveCameraSource.applyRotation(videoRotationAngle, to: connection)
    }

    private func applyStillImage() {
        let showStill = session == nil && stillImage != nil
        imageView.isHidden = !showStill
        if showStill, let stillImage {
            imageView.image = UIImage(cgImage: stillImage)
        } else {
            imageView.image = nil
        }
    }
}
