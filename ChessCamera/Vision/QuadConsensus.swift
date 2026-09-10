import CoreGraphics
import Foundation

/// Requires several similar detections before accepting a board quad.
struct QuadConsensus: Sendable {
    var needed: Int
    var similarityFraction: CGFloat

    private var recent: [Quadrilateral] = []

    init(needed: Int = 5, similarityFraction: CGFloat = 0.1) {
        self.needed = needed
        self.similarityFraction = similarityFraction
    }

    mutating func reset() {
        recent = []
    }

    var count: Int { recent.count }

    /// Ingest a detection. Returns a blended consensus quad once `needed` similar hits arrive.
    mutating func ingest(_ quad: Quadrilateral, imageSize: CGSize) -> Quadrilateral? {
        if let last = recent.last, last.isSimilar(to: quad, imageSize: imageSize, fraction: similarityFraction) {
            recent.append(quad)
        } else {
            recent = [quad]
        }
        guard recent.count >= needed else { return nil }
        let consensus = Self.average(recent)
        recent = []
        return consensus
    }

    static func average(_ quads: [Quadrilateral]) -> Quadrilateral {
        precondition(!quads.isEmpty)
        let n = CGFloat(quads.count)
        func mean(_ keyPath: KeyPath<Quadrilateral, CGPoint>) -> CGPoint {
            let sum = quads.reduce(into: CGPoint.zero) { partial, q in
                let p = q[keyPath: keyPath]
                partial.x += p.x
                partial.y += p.y
            }
            return CGPoint(x: sum.x / n, y: sum.y / n)
        }
        return Quadrilateral(
            topLeft: mean(\.topLeft),
            topRight: mean(\.topRight),
            bottomRight: mean(\.bottomRight),
            bottomLeft: mean(\.bottomLeft)
        )
    }
}
