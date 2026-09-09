import SwiftUI

struct CornerCalibrationView: View {
    @Bindable var model: RecordingSessionViewModel
    @State private var viewSize: CGSize = .zero

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    CameraPreview(session: model.liveCaptureSession, stillImage: model.previewImage)
                    BoardQuadOverlay(
                        quad: model.quad,
                        bufferSize: model.bufferSize,
                        style: .locked,
                        pulse: false
                    )
                    handles(in: size)
                }
                .onAppear { viewSize = size }
                .onChange(of: proxy.size) { _, newSize in viewSize = newSize }
            }
            VStack {
                Text("Drag the corners of the board.")
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.overlayScrim)
                Spacer()
                VStack(spacing: 12) {
                    PrimaryButton(title: "Use these corners") {
                        Task { await model.useTheseCorners() }
                    }
                    SecondaryButton(title: "Cancel") {
                        model.cancelCalibration()
                    }
                }
                .padding(16)
                .background(Theme.surface.opacity(0.95))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if model.quad == nil {
                model.adjustCorners()
            }
        }
    }

    @ViewBuilder
    private func handles(in size: CGSize) -> some View {
        if let quad = model.quad, model.bufferSize.width > 0 {
            let points = [
                VideoMapping.bufferToView(point: quad.topLeft, viewSize: size, bufferSize: model.bufferSize),
                VideoMapping.bufferToView(point: quad.topRight, viewSize: size, bufferSize: model.bufferSize),
                VideoMapping.bufferToView(point: quad.bottomRight, viewSize: size, bufferSize: model.bufferSize),
                VideoMapping.bufferToView(point: quad.bottomLeft, viewSize: size, bufferSize: model.bufferSize)
            ]
            ForEach(0..<4, id: \.self) { index in
                CornerHandle(label: "\(index + 1)", point: points[index]) { location in
                    let clamped = VideoMapping.clampToVideo(
                        point: location,
                        viewSize: size,
                        bufferSize: model.bufferSize
                    )
                    if let bufferPoint = VideoMapping.viewToBuffer(
                        point: clamped,
                        viewSize: size,
                        bufferSize: model.bufferSize
                    ) {
                        model.setCorner(index, bufferPoint: bufferPoint)
                    }
                }
            }
        }
    }
}

private struct CornerHandle: View {
    var label: String
    var point: CGPoint
    var onDrag: (CGPoint) -> Void
    @State private var dragOrigin: CGPoint?

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 16, height: 16)
            .overlay {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .offset(y: -22)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = point }
                        if let dragOrigin {
                            onDrag(
                                CGPoint(
                                    x: dragOrigin.x + value.translation.width,
                                    y: dragOrigin.y + value.translation.height
                                )
                            )
                        }
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                    }
            )
            .accessibilityLabel("Corner \(label)")
    }
}
