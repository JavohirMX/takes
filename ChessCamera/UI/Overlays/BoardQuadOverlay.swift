import SwiftUI

enum QuadOverlayStyle {
    case detecting
    case locked
    case poor
    /// Secondary overlay for ML compare in Board Studio.
    case mlCompare

    var color: Color {
        switch self {
        case .detecting: Color.white.opacity(0.8)
        case .locked: Theme.accent
        case .poor: Theme.caution
        case .mlCompare: Theme.accent.opacity(0.9)
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .mlCompare: 2.5
        default: 3
        }
    }
}

struct BoardQuadOverlay: View {
    var quad: Quadrilateral?
    var bufferSize: CGSize
    var style: QuadOverlayStyle
    var pulse: Bool

    var body: some View {
        GeometryReader { proxy in
            if let quad, bufferSize.width > 0 {
                let mapped = quad.points.map {
                    VideoMapping.bufferToView(point: $0, viewSize: proxy.size, bufferSize: bufferSize)
                }
                Path { path in
                    guard let first = mapped.first else { return }
                    path.move(to: first)
                    for point in mapped.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.closeSubpath()
                }
                .stroke(style.color, lineWidth: style.lineWidth)
                .opacity(pulse ? 0.55 : 1)
                .animation(pulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.2), value: pulse)
            }
        }
        .allowsHitTesting(false)
    }
}
