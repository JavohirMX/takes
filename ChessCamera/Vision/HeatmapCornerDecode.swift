import CoreGraphics
import Foundation

/// Geometry helpers matching Elucidation chessdetect-tfjs preprocess + heatmap decode.
enum HeatmapCornerDecode {
    static let modelSize = 128

    /// Center-crop square in source pixel space (same math as TF.js `preprocessSource`).
    static func centerCropSquare(srcSize: CGSize) -> CGRect {
        let width = srcSize.width
        let height = srcSize.height
        guard width > 0, height > 0 else { return .zero }
        let aspect = width / height
        let cropWidth: CGFloat
        let cropHeight: CGFloat
        if aspect > 1 {
            cropWidth = height
            cropHeight = height
        } else {
            cropWidth = width
            cropHeight = width
        }
        let originX = (width - cropWidth) / 2
        let originY = (height - cropHeight) / 2
        return CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
    }

    /// Map a peak in 128×128 model space back to full buffer pixels through the center crop.
    static func mapPeakToBuffer(
        peakIn128: CGPoint,
        cropRect: CGRect,
        modelSize: Int = modelSize
    ) -> CGPoint {
        let s = CGFloat(modelSize)
        guard s > 0, cropRect.width > 0, cropRect.height > 0 else { return .zero }
        let u = peakIn128.x / s
        let v = peakIn128.y / s
        return CGPoint(
            x: cropRect.minX + u * cropRect.width,
            y: cropRect.minY + v * cropRect.height
        )
    }

    struct Peak: Equatable, Sendable {
        var x: Int
        var y: Int
        var score: Float
        var point: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
    }

    /// `corners` is row-major HxWx4 (channels last): TL, TR, BR, BL.
    static func argmaxPeaks(corners: [Float], height: Int, width: Int, channels: Int = 4) -> [Peak] {
        precondition(channels == 4)
        precondition(corners.count == height * width * channels)
        var peaks: [Peak] = []
        peaks.reserveCapacity(channels)
        for c in 0..<channels {
            var bestIdx = 0
            var bestScore = -Float.greatestFiniteMagnitude
            for i in 0..<(height * width) {
                let score = corners[i * channels + c]
                if score > bestScore {
                    bestScore = score
                    bestIdx = i
                }
            }
            let y = bestIdx / width
            let x = bestIdx % width
            peaks.append(Peak(x: x, y: y, score: bestScore))
        }
        return peaks
    }

    static func quadFromPeaks(
        _ peaks: [Peak],
        cropRect: CGRect,
        bufferSize: CGSize,
        minimumScore: Float = 0.05,
        minimumSizeFraction: CGFloat = 0.12
    ) -> Quadrilateral? {
        guard peaks.count == 4 else { return nil }
        guard peaks.allSatisfy({ $0.score.isFinite && $0.score >= minimumScore }) else { return nil }
        let mapped = peaks.map {
            mapPeakToBuffer(peakIn128: $0.point, cropRect: cropRect)
        }
        let quad = Quadrilateral(
            topLeft: mapped[0],
            topRight: mapped[1],
            bottomRight: mapped[2],
            bottomLeft: mapped[3]
        ).clamped(to: bufferSize)
        let width = hypot(quad.topRight.x - quad.topLeft.x, quad.topRight.y - quad.topLeft.y)
        let height = hypot(quad.bottomLeft.x - quad.topLeft.x, quad.bottomLeft.y - quad.topLeft.y)
        let minDim = min(bufferSize.width, bufferSize.height)
        guard width > 1, height > 1, min(width, height) / max(minDim, 1) >= minimumSizeFraction else {
            return nil
        }
        // Reject crossed / degenerate quads (self-intersecting roughly).
        let area = abs(quadArea(quad))
        guard area > (minDim * minDim * 0.01) else { return nil }
        return quad
    }

    private static func quadArea(_ q: Quadrilateral) -> CGFloat {
        let pts = q.points
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = pts[i]
            let b = pts[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }
}
