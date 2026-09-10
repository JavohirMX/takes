import SwiftUI
import UIKit

struct BoardStudioView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var cameraSize: CGSize = .zero

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isLandscape {
                landscape
            } else {
                portrait
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            Task { await model.startCaptureIfNeeded() }
        }
    }

    private var portrait: some View {
        VStack(spacing: 0) {
            cameraPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .center, spacing: 12) {
                WarpedBoardView(image: model.warpedThumbnail, orientation: model.orientation)
                    .frame(width: 140, height: 140)
                controls
            }
            .padding(12)
            .background(Theme.surface.opacity(0.95))
        }
    }

    private var landscape: some View {
        HStack(spacing: 0) {
            cameraPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 12) {
                WarpedBoardView(image: model.warpedThumbnail, orientation: model.orientation)
                    .frame(maxWidth: 280, maxHeight: 280)
                controls
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 300)
            .background(Theme.surface.opacity(0.95))
        }
    }

    private var cameraPane: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreview(
                    session: model.liveCaptureSession,
                    stillImage: model.isVideoImport ? model.previewImage : nil
                )
                if model.cameraUnavailable {
                    Text("Camera unavailable")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                } else if !model.isCaptureRunning {
                    ProgressView()
                        .tint(Theme.accent)
                }
                if let quad = model.quad, model.bufferSize.width > 0 {
                    BoardQuadOverlay(
                        quad: quad,
                        bufferSize: model.bufferSize,
                        style: model.trackingWeak ? .poor : .locked,
                        pulse: false
                    )
                    BoardGridOverlay(quad: quad, bufferSize: model.bufferSize)
                    handles(in: proxy.size)
                }
            }
            .onAppear { cameraSize = proxy.size }
            .onChange(of: proxy.size) { _, size in cameraSize = size }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusCopy)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(hintCopy)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.quad != nil {
                PrimaryButton(title: "Looks good") {
                    Task { await model.confirmQuad() }
                }
            } else if model.detectTimedOut {
                PrimaryButton(title: "Place corners") {
                    model.placeManualCorners()
                }
            }
            HStack(spacing: 12) {
                Button("Rescan") {
                    Task { await model.rescanBoard() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                Button("Flip") {
                    Task { await model.flipBoard() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Flip board")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        }
    }

    private var statusCopy: String {
        if model.trackingWeak {
            return "Tracking weak — drag the corners onto the squares."
        }
        if model.quad == nil {
            if model.detectTimedOut {
                return "Couldn’t find the board — place the four corners."
            }
            return "Looking for the board…"
        }
        return "Corners ready — tap Looks good."
    }

    private var hintCopy: String {
        if model.quad == nil, model.detectTimedOut {
            return "Tap Place corners, then drag each handle onto a board corner."
        }
        if isLandscape {
            return "Drag the four corners onto the board corners if needed."
        }
        return "Turn the phone sideways, or drag the four corners onto the board."
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
                CornerHandle(label: "\(index + 1)", point: points[index], onDrag: { location in
                    model.beginCornerDrag()
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
                }, onEnded: {
                    model.finishCornerDrag()
                })
            }
        }
    }
}
