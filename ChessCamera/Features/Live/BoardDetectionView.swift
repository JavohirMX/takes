import SwiftUI
import UIKit

struct BoardDetectionView: View {
    @Bindable var model: RecordingSessionViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            cameraStack
            VStack {
                Spacer()
                caption
                controls
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cameraStack: some View {
        ZStack {
            CameraPreview(session: model.liveCaptureSession, stillImage: model.previewImage)
            BoardQuadOverlay(
                quad: model.quad,
                bufferSize: model.bufferSize,
                style: model.quad == nil ? .detecting : .locked,
                pulse: model.quad == nil && !UIAccessibility.isReduceMotionEnabled
            )
            if let thumb = model.warpedThumbnail {
                VStack {
                    HStack {
                        Spacer()
                        Image(uiImage: UIImage(cgImage: thumb))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 1)
                            }
                            .padding(16)
                    }
                    Spacer()
                }
                .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    private var caption: some View {
        VStack(spacing: 8) {
            Text("Fit the whole board in view.")
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Text(model.quad == nil ? "Looking for the board…" : "Board found")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            if model.cameraUnavailable {
                Text("Camera unavailable. Adjust corners to continue, or import a video from History.")
                    .font(.callout)
                    .foregroundStyle(Theme.caution)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.overlayScrim)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if model.quad != nil {
                PrimaryButton(title: "Looks good") {
                    Task { await model.confirmQuad() }
                }
            }
            SecondaryButton(
                title: "Adjust corners",
                action: { model.adjustCorners() }
            )
        }
        .padding(16)
        .background(Theme.surface.opacity(0.95))
    }
}
