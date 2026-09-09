import CoreGraphics
import Foundation

struct Quadrilateral: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    var points: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    static func insetRect(in size: CGSize, fraction: CGFloat = 0.12) -> Quadrilateral {
        let dx = size.width * fraction
        let dy = size.height * fraction
        return Quadrilateral(
            topLeft: CGPoint(x: dx, y: dy),
            topRight: CGPoint(x: size.width - dx, y: dy),
            bottomRight: CGPoint(x: size.width - dx, y: size.height - dy),
            bottomLeft: CGPoint(x: dx, y: size.height - dy)
        )
    }

    func clamped(to size: CGSize) -> Quadrilateral {
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(p.x, 0), size.width),
                y: min(max(p.y, 0), size.height)
            )
        }
        return Quadrilateral(
            topLeft: clamp(topLeft),
            topRight: clamp(topRight),
            bottomRight: clamp(bottomRight),
            bottomLeft: clamp(bottomLeft)
        )
    }
}
