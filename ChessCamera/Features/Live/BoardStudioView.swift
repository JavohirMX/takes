import SwiftUI
import UIKit

struct BoardStudioView: View {
    @Bindable var model: RecordingSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var cameraSize: CGSize = .zero

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        let layout = isLandscape
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        layout {
            cameraPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            accessory
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(nil, value: verticalSizeClass)
        .onAppear {
            Task { await model.startCaptureIfNeeded() }
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if isLandscape {
            VStack(spacing: 12) {
                WarpedBoardView(
                    image: model.warpedThumbnail,
                    orientation: model.orientation,
                    grid: model.refinedGrid
                )
                .frame(maxWidth: 280, maxHeight: 280)
                controls
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 300)
            .background(Theme.surface.opacity(0.95))
        } else {
            HStack(alignment: .center, spacing: 12) {
                WarpedBoardView(
                    image: model.warpedThumbnail,
                    orientation: model.orientation,
                    grid: model.refinedGrid
                )
                .frame(width: 140, height: 140)
                controls
            }
            .padding(12)
            .background(Theme.surface.opacity(0.95))
        }
    }

    private var cameraPane: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreview(
                    session: model.liveCaptureSession,
                    stillImage: model.isVideoImport ? model.previewImage : nil,
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
                    if let vision = model.visionQuad {
                        BoardQuadOverlay(
                            quad: vision,
                            bufferSize: model.bufferSize,
                            style: .detecting,
                            pulse: model.activeLocalizer != .vision
                        )
                    }
                    if let ml = model.mlQuad {
                        BoardQuadOverlay(
                            quad: ml,
                            bufferSize: model.bufferSize,
                            style: .mlCompare,
                            pulse: model.activeLocalizer != .ml
                        )
                    }
                    if let quad = model.quad {
                        BoardGridOverlay(
                            quad: quad,
                            bufferSize: model.bufferSize,
                            grid: model.refinedGrid
                        )
                        handles(in: proxy.size)
                    }
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
            if model.isHeatmapLocalizerAvailable || model.mlQuad != nil || model.visionQuad != nil {
                localizerPicker
            }
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
                Button("Rotate") {
                    Task { await model.rotateBoard() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Rotate board")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        }
    }

    private var localizerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Localizer", selection: Binding(
                get: { model.activeLocalizer },
                set: { model.setActiveLocalizer($0) }
            )) {
                Text(BoardLocalizerSource.vision.title)
                    .tag(BoardLocalizerSource.vision)
                    .disabled(model.visionQuad == nil)
                Text(BoardLocalizerSource.ml.title)
                    .tag(BoardLocalizerSource.ml)
                    .disabled(model.mlQuad == nil)
            }
            .pickerStyle(.segmented)
            .disabled(model.visionQuad == nil && model.mlQuad == nil)
            Text(compareStatusCopy)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var compareStatusCopy: String {
        let visionMark = model.visionQuad != nil ? "✓" : "—"
        let mlMark: String
        if !model.isHeatmapLocalizerAvailable {
            mlMark = "n/a"
        } else {
            mlMark = model.mlQuad != nil ? "✓" : "—"
        }
        return "Vision \(visionMark)  ML \(mlMark) — active: \(model.activeLocalizer.title)"
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
        if model.trackingWeak {
            return "If the outline stays off, wait a moment for rescan or drag the corners."
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
