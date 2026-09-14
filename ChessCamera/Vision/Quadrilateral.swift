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

    /// Inverse of `interpolated(u:v:)`. Nil when `point` is outside the quad.
    func uv(containing point: CGPoint, epsilon: CGFloat = 1e-4) -> CGPoint? {
        let a = topLeft
        let b = topRight
        let c = bottomRight
        let d = bottomLeft
        let e = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let f = CGPoint(x: d.x - a.x, y: d.y - a.y)
        let g = CGPoint(x: a.x - b.x + c.x - d.x, y: a.y - b.y + c.y - d.y)
        let h = CGPoint(x: point.x - a.x, y: point.y - a.y)

        func cross(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
            lhs.x * rhs.y - lhs.y * rhs.x
        }

        func u(forV v: CGFloat) -> CGFloat? {
            let denomX = e.x + g.x * v
            let denomY = e.y + g.y * v
            if abs(denomX) >= abs(denomY), abs(denomX) > 1e-10 {
                return (h.x - f.x * v) / denomX
            }
            if abs(denomY) > 1e-10 {
                return (h.y - f.y * v) / denomY
            }
            return nil
        }

        func clamped(_ u: CGFloat, _ v: CGFloat) -> CGPoint? {
            guard u >= -epsilon, v >= -epsilon, u <= 1 + epsilon, v <= 1 + epsilon else {
                return nil
            }
            return CGPoint(x: min(max(u, 0), 1), y: min(max(v, 0), 1))
        }

        let k2 = cross(g, f)
        let k1 = cross(e, f) + cross(h, g)
        let k0 = cross(h, e)

        if abs(k2) < 1e-10 {
            guard abs(k1) > 1e-10 else { return nil }
            let v = -k0 / k1
            guard let u = u(forV: v) else { return nil }
            return clamped(u, v)
        }

        let discriminant = k1 * k1 - 4 * k0 * k2
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let vMinus = (-k1 - root) / (2 * k2)
        let vPlus = (-k1 + root) / (2 * k2)
        if let u = u(forV: vMinus), let uv = clamped(u, vMinus) {
            return uv
        }
        if let u = u(forV: vPlus), let uv = clamped(u, vPlus) {
            return uv
        }
        return nil
    }

    /// Camera-buffer point → algebraic square using the same bilinear grid as `BoardGridOverlay`.
    func square(containingCameraPoint point: CGPoint, orientation: BoardOrientation) -> ChessSquare? {
        guard let uv = uv(containing: point) else { return nil }
        let fileIndex = min(7, Int(uv.x * 8))
        let rankFromImageTop = min(7, Int(uv.y * 8))
        return GridSampler.square(
            fileIndex: fileIndex,
            rankFromImageTop: rankFromImageTop,
            orientation: orientation
        )
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

    /// Grow the quad in UV space so OpenCV can see the full 8×8 square-grid.
    /// `fraction` 0.15 adds 15% of the board side on each edge.
    func expanded(by fraction: CGFloat) -> Quadrilateral {
        let lo = -fraction
        let hi = 1 + fraction
        return Quadrilateral(
            topLeft: interpolated(u: lo, v: lo),
            topRight: interpolated(u: hi, v: lo),
            bottomRight: interpolated(u: hi, v: hi),
            bottomLeft: interpolated(u: lo, v: hi)
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
