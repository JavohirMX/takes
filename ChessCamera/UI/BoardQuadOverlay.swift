import SwiftUI

enum QuadOverlayStyle {
    case detecting
    case locked
    case poor

    var color: Color {
        switch self {
        case .detecting: Color.white.opacity(0.8)
        case .locked: Theme.accent
        case .poor: Theme.caution
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
                .stroke(style.color, lineWidth: 3)
                .opacity(pulse ? 0.55 : 1)
                .animation(pulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.2), value: pulse)
            }
        }
        .allowsHitTesting(false)
    }
}
