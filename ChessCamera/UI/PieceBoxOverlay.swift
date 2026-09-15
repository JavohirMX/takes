import SwiftUI

struct PieceBoxOverlay: View {
    var boxes: [PieceDetection.Box]
    var bufferSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            ForEach(boxes) { box in
                let rect = VideoMapping.bufferToView(
                    rect: box.bufferRect,
                    viewSize: proxy.size,
                    bufferSize: bufferSize
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(box.overlayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .frame(width: max(rect.width, 1), height: max(rect.height, 1), alignment: .topLeading)
                .overlay {
                    Rectangle()
                        .stroke(Theme.accent, lineWidth: 2)
                }
                .position(x: rect.midX, y: rect.midY)
                .accessibilityLabel(box.overlayLabel)
            }
        }
        .allowsHitTesting(false)
    }
}

/// YOLO boxes in tight playing-surface UV. Warp maps UV × view size; camera maps corners through the locked quad.
struct YOLOBoxOverlay: View {
    var boxes: [PieceDetection.OverlayBox]
    var quad: Quadrilateral? = nil
    var bufferSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for box in boxes {
                    let corners = mappedCorners(of: box.uvRect, viewSize: size)
                    guard corners.count == 4 else { continue }
                    var path = Path()
                    path.move(to: corners[0])
                    path.addLine(to: corners[1])
                    path.addLine(to: corners[2])
                    path.addLine(to: corners[3])
                    path.closeSubpath()
                    context.stroke(path, with: .color(Theme.accent), lineWidth: 2)
                }
            }
            ForEach(boxes) { box in
                let corners = mappedCorners(of: box.uvRect, viewSize: proxy.size)
                let labelPoint = labelOrigin(for: corners)
                Text(box.overlayLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize()
                    .position(x: labelPoint.x, y: labelPoint.y)
                    .accessibilityLabel(box.overlayLabel)
            }
        }
        .allowsHitTesting(false)
    }

    private func mappedCorners(of uv: CGRect, viewSize: CGSize) -> [CGPoint] {
        let points = [
            CGPoint(x: uv.minX, y: uv.minY),
            CGPoint(x: uv.maxX, y: uv.minY),
            CGPoint(x: uv.maxX, y: uv.maxY),
            CGPoint(x: uv.minX, y: uv.maxY),
        ]
        return points.map { point in
            if let quad, bufferSize.width > 0, bufferSize.height > 0 {
                return VideoMapping.bufferToView(
                    point: quad.perspectiveMapped(u: point.x, v: point.y),
                    viewSize: viewSize,
                    bufferSize: bufferSize
                )
            }
            return CGPoint(x: point.x * viewSize.width, y: point.y * viewSize.height)
        }
    }

    private func labelOrigin(for corners: [CGPoint]) -> CGPoint {
        guard let first = corners.first else { return .zero }
        let minX = corners.map(\.x).min() ?? first.x
        let minY = corners.map(\.y).min() ?? first.y
        return CGPoint(x: minX + 4, y: minY + 8)
    }
}
