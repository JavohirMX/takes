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

    /// `u` is left→right, `v` is top→bottom in the warped board, both 0...1.
    func interpolated(u: CGFloat, v: CGFloat) -> CGPoint {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let top = lerp(topLeft, topRight, u)
        let bottom = lerp(bottomLeft, bottomRight, u)
        return lerp(top, bottom, v)
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

    func blended(with other: Quadrilateral, t: CGFloat) -> Quadrilateral {
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return Quadrilateral(
            topLeft: mix(topLeft, other.topLeft),
            topRight: mix(topRight, other.topRight),
            bottomRight: mix(bottomRight, other.bottomRight),
            bottomLeft: mix(bottomLeft, other.bottomLeft)
        )
    }

    func maxCornerDistance(to other: Quadrilateral) -> CGFloat {
        zip(points, other.points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// True when every corner moved less than `fraction` of the shorter image side.
    func isSimilar(to other: Quadrilateral, imageSize: CGSize, fraction: CGFloat = 0.12) -> Bool {
        let limit = min(imageSize.width, imageSize.height) * fraction
        return maxCornerDistance(to: other) <= limit
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

    func scaled(by factor: CGFloat) -> Quadrilateral {
        func scale(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * factor, y: p.y * factor)
        }
        return Quadrilateral(
            topLeft: scale(topLeft),
            topRight: scale(topRight),
            bottomRight: scale(bottomRight),
            bottomLeft: scale(bottomLeft)
        )
    }
}
