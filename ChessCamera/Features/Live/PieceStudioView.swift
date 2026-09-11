import SwiftUI

struct PieceStudioView: View {
    @Bindable var model: RecordingSessionViewModel

    var body: some View {
        ZStack {
            CameraPreview(
                session: model.liveCaptureSession,
                videoRotationAngle: model.previewRotationAngle
            )
            if model.cameraUnavailable {
                Text("Camera unavailable")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            } else if !model.isCaptureRunning {
                ProgressView()
                    .tint(Theme.accent)
            }
            if model.bufferSize.width > 0 {
                PieceBoxOverlay(boxes: model.pieceBoxes, bufferSize: model.bufferSize)
            }
            if !model.pieceDetectorAvailable {
                VStack {
                    Spacer()
                    Text("No piece detector bundled.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.overlayScrim, in: RoundedRectangle(cornerRadius: 12))
                        .padding(16)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            Task { await model.startCaptureIfNeeded() }
        }
    }
}
