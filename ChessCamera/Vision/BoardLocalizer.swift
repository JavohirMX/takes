import CoreImage
import CoreVideo
import Foundation
import Vision

struct VisionBoardLocalizer: BoardLocalizer {
    private static let maxVisionSide: CGFloat = 1280
    private static let scoreWarpSize = 128
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    func detect(in buffer: CVPixelBuffer) async -> Quadrilateral? {
        let fullWidth = CGFloat(CVPixelBufferGetWidth(buffer))
        let fullHeight = CGFloat(CVPixelBufferGetHeight(buffer))
        guard fullWidth > 0, fullHeight > 0 else { return nil }

        let (visionBuffer, scale) = Self.downscaled(buffer, maxSide: Self.maxVisionSide) ?? (buffer, 1)
        let width = CGFloat(CVPixelBufferGetWidth(visionBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(visionBuffer))
        guard width > 0, height > 0 else { return nil }

        let request = VNDetectRectanglesRequest()
        // Angled boards are trapezoids, not squares, in the camera frame.
        request.minimumAspectRatio = 0.4
        request.maximumAspectRatio = 2.5
        request.minimumSize = 0.18
        request.quadratureTolerance = 45
        request.minimumConfidence = 0.25
        request.maximumObservations = 8

        let handler = VNImageRequestHandler(cvPixelBuffer: visionBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let found = (request.results as? [VNRectangleObservation]) ?? []
        let imageSize = CGSize(width: width, height: height)
        let candidates = found.compactMap { observation -> (quad: Quadrilateral, score: CGFloat)? in
            let quad = Self.pixelQuad(from: observation, width: width, height: height)
            let score = Self.score(
                quad,
                in: visionBuffer,
                imageSize: imageSize,
                confidence: CGFloat(observation.confidence)
            )
            guard score > 0 else { return nil }
            return (quad, score)
        }
        guard let best = candidates.max(by: { $0.score < $1.score })?.quad else { return nil }
        if scale == 1 { return best }
        return best.scaled(by: 1 / scale)
    }

    private static func pixelQuad(from observation: VNRectangleObservation, width: CGFloat, height: CGFloat) -> Quadrilateral {
        func pixel(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * width, y: (1 - p.y) * height)
        }
        return Quadrilateral(
            topLeft: pixel(observation.topLeft),
            topRight: pixel(observation.topRight),
            bottomRight: pixel(observation.bottomRight),
            bottomLeft: pixel(observation.bottomLeft)
        )
    }

    /// Warp-then-verify: size + soft aspect + Vision confidence × occlusion-tolerant grid likeness.
    static func score(
        _ quad: Quadrilateral,
        in buffer: CVPixelBuffer,
        imageSize: CGSize,
        confidence: CGFloat
    ) -> CGFloat {
        let width = hypot(quad.topRight.x - quad.topLeft.x, quad.topRight.y - quad.topLeft.y)
        let height = hypot(quad.bottomLeft.x - quad.topLeft.x, quad.bottomLeft.y - quad.topLeft.y)
        guard width > 0, height > 0 else { return 0 }
        let aspect = width / height
        guard aspect >= 0.4, aspect <= 2.5 else { return 0 }
        let minDim = min(imageSize.width, imageSize.height)
        let sizeFraction = min(width, height) / minDim
        guard sizeFraction >= 0.18 else { return 0 }

        let softAspect = 1 - min(1, abs(1 - aspect) * 0.35)
        guard let warped = BoardWarper.warp(buffer, quad: quad, size: scoreWarpSize) else { return 0 }
        let grid = ChessboardGridScore.score(cgImage: warped.squareImage)
        guard grid > 0.08 else { return 0 }

        // Size is squared so a large trapezoid board beats a small inner 4×4.
        return sizeFraction * sizeFraction * softAspect * (0.5 + confidence) * (0.35 + grid)
    }

    /// Expose scoring for tests without Vision.
    static func scoreWarpedGrid(_ image: CGImage) -> CGFloat {
        ChessboardGridScore.score(cgImage: image)
    }

    private static func downscaled(_ buffer: CVPixelBuffer, maxSide: CGFloat) -> (CVPixelBuffer, CGFloat)? {
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        let longest = max(width, height)
        guard longest > maxSide else { return (buffer, 1) }
        let scale = maxSide / longest
        let outW = Int((width * scale).rounded())
        let outH = Int((height * scale).rounded())
        guard outW > 1, outH > 1 else { return nil }

        var formatted: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            outW,
            outH,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &formatted
        )
        guard status == kCVReturnSuccess, let output = formatted else { return nil }

        let input = CIImage(cvPixelBuffer: buffer)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        context.render(scaled, to: output)
        return (output, scale)
    }
}

protocol BoardLocalizer: Sendable {
    func detect(in buffer: CVPixelBuffer) async -> Quadrilateral?
}
