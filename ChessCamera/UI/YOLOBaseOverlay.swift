import SwiftUI

/// Debug dots at YOLO piece anchors (box center of each detection), colored by piece side.
struct YOLOBaseOverlay: View {
    var bases: [PieceDetection.BaseDot]
    var quad: Quadrilateral? = nil
    var bufferSize: CGSize = .zero
    var diameter: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            for dot in bases {
                let center: CGPoint
                if let quad, bufferSize.width > 0, bufferSize.height > 0 {
                    center = VideoMapping.bufferToView(
                        point: quad.perspectiveMapped(u: dot.uv.x, v: dot.uv.y),
                        viewSize: size,
                        bufferSize: bufferSize
                    )
                } else {
                    center = CGPoint(x: dot.uv.x * size.width, y: dot.uv.y * size.height)
                }
                let rect = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                let (fillColor, borderColor): (Color, Color) = {
                    switch dot.piece.pieceColor {
                    case .white:
                        return (.white, .black)
                    case .black:
                        return (Color(white: 0.12), .white)
                    case nil:
                        return (Theme.danger, .white)
                    }
                }()
                let path = Path(ellipseIn: rect)
                context.fill(path, with: .color(fillColor))
                context.stroke(path, with: .color(borderColor), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
