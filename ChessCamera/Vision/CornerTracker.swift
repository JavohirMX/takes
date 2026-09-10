import CoreGraphics
import CoreVideo
import Foundation

struct GrayFrame: Sendable {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    subscript(x: Int, y: Int) -> UInt8 {
        let cx = min(max(x, 0), width - 1)
        let cy = min(max(y, 0), height - 1)
        return pixels[cy * width + cx]
    }

    func patch(centeredAt center: CGPoint, size: Int) -> [UInt8] {
        let half = size / 2
        var out = [UInt8](repeating: 0, count: size * size)
        let cx = Int(center.x.rounded())
        let cy = Int(center.y.rounded())
        var i = 0
        for dy in -half..<(size - half) {
            for dx in -half..<(size - half) {
                out[i] = self[cx + dx, cy + dy]
                i += 1
            }
        }
        return out
    }

    static func from(_ buffer: CVPixelBuffer) -> GrayFrame? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = ptr.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let i = x * 4
                let b = Double(row[i])
                let g = Double(row[i + 1])
                let r = Double(row[i + 2])
                pixels[y * width + x] = UInt8((0.114 * b + 0.587 * g + 0.299 * r).rounded())
            }
        }
        return GrayFrame(width: width, height: height, pixels: pixels)
    }

    static func from(cgImage: CGImage) -> GrayFrame? {
        let width = cgImage.width
        let height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let o = i * 4
            let r = Double(data[o])
            let g = Double(data[o + 1])
            let b = Double(data[o + 2])
            pixels[i] = UInt8((0.299 * r + 0.587 * g + 0.114 * b).rounded())
        }
        return GrayFrame(width: width, height: height, pixels: pixels)
    }
}

enum NormalizedCorrelation {
    static func score(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let n = Double(a.count)
        var meanA = 0.0
        var meanB = 0.0
        for i in 0..<a.count {
            meanA += Double(a[i])
            meanB += Double(b[i])
        }
        meanA /= n
        meanB /= n
        var num = 0.0
        var da = 0.0
        var db = 0.0
        for i in 0..<a.count {
            let xa = Double(a[i]) - meanA
            let xb = Double(b[i]) - meanB
            num += xa * xb
            da += xa * xa
            db += xb * xb
        }
        let den = sqrt(da * db)
        guard den > 1e-6 else { return 0 }
        return num / den
    }
}

struct CornerTrackResult: Equatable, Sendable {
    var quad: Quadrilateral
    var confidences: [Double]
    var minConfidence: Double { confidences.min() ?? 0 }
}

struct CornerTracker: Sendable {
    var patchSize: Int = 21
    var searchRadius: Int = 36
    var minimumScore: Double = 0.55

    private var templates: [[UInt8]] = []

    init(patchSize: Int = 21, searchRadius: Int = 36, minimumScore: Double = 0.55) {
        self.patchSize = patchSize
        self.searchRadius = searchRadius
        self.minimumScore = minimumScore
    }

    var hasTemplates: Bool { templates.count == 4 }

    mutating func reset() {
        templates = []
    }

    mutating func capture(from frame: GrayFrame, quad: Quadrilateral) {
        templates = quad.points.map { frame.patch(centeredAt: $0, size: patchSize) }
    }

    func track(in frame: GrayFrame, from quad: Quadrilateral) -> CornerTrackResult {
        guard templates.count == 4 else {
            return CornerTrackResult(quad: quad, confidences: [0, 0, 0, 0])
        }
        var points = quad.points
        var confidences = [Double](repeating: 0, count: 4)
        for i in 0..<4 {
            let (point, score) = Self.bestMatch(
                template: templates[i],
                in: frame,
                around: points[i],
                patchSize: patchSize,
                searchRadius: searchRadius
            )
            confidences[i] = score
            if score >= minimumScore {
                points[i] = point
            }
        }
        let tracked = Quadrilateral(
            topLeft: points[0],
            topRight: points[1],
            bottomRight: points[2],
            bottomLeft: points[3]
        )
        return CornerTrackResult(quad: tracked.clamped(to: CGSize(width: frame.width, height: frame.height)), confidences: confidences)
    }

    static func bestMatch(
        template: [UInt8],
        in frame: GrayFrame,
        around center: CGPoint,
        patchSize: Int,
        searchRadius: Int
    ) -> (CGPoint, Double) {
        let cx = Int(center.x.rounded())
        let cy = Int(center.y.rounded())
        var best = center
        var bestScore = -1.0
        for y in stride(from: cy - searchRadius, through: cy + searchRadius, by: 2) {
            for x in stride(from: cx - searchRadius, through: cx + searchRadius, by: 2) {
                let candidate = CGPoint(x: x, y: y)
                let patch = frame.patch(centeredAt: candidate, size: patchSize)
                let score = NormalizedCorrelation.score(template, patch)
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }
        }
        // Refine 1px around the coarse peak.
        let rx = Int(best.x.rounded())
        let ry = Int(best.y.rounded())
        for y in (ry - 1)...(ry + 1) {
            for x in (rx - 1)...(rx + 1) {
                let candidate = CGPoint(x: x, y: y)
                let patch = frame.patch(centeredAt: candidate, size: patchSize)
                let score = NormalizedCorrelation.score(template, patch)
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }
        }
        return (best, bestScore)
    }
}
