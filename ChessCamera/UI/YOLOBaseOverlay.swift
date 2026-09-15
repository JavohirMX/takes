import SwiftUI

/// Debug dots at YOLO piece anchors (box center of each detection).
struct YOLOBaseOverlay: View {
    var bases: [CGPoint]
    var quad: Quadrilateral? = nil
    var bufferSize: CGSize = .zero
    var diameter: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            for uv in bases {
                let center: CGPoint
                if let quad, bufferSize.width > 0, bufferSize.height > 0 {
                    center = VideoMapping.bufferToView(
                        point: quad.perspectiveMapped(u: uv.x, v: uv.y),
                        viewSize: size,
                        bufferSize: bufferSize
                    )
                } else {
                    center = CGPoint(x: uv.x * size.width, y: uv.y * size.height)
                }
                let rect = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(Theme.danger))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
