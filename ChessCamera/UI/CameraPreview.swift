import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    var session: AVCaptureSession?
    var stillImage: CGImage?

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if let session {
            uiView.imageView.isHidden = true
            uiView.previewLayer.isHidden = false
            if uiView.previewLayer.session !== session {
                uiView.previewLayer.session = session
            }
        } else {
            uiView.previewLayer.session = nil
            uiView.previewLayer.isHidden = true
            uiView.imageView.isHidden = false
            if let stillImage {
                uiView.imageView.image = UIImage(cgImage: stillImage)
            } else {
                uiView.imageView.image = nil
            }
        }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.isHidden = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }
}
