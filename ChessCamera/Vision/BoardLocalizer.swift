import CoreVideo
import Foundation
import Vision

struct VisionBoardLocalizer: BoardLocalizer {
    func detect(in buffer: CVPixelBuffer) async -> Quadrilateral? {
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        guard width > 0, height > 0 else { return nil }

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.8
        request.maximumAspectRatio = 1.25
        request.minimumSize = 0.35
        request.quadratureTolerance = 20
        request.minimumConfidence = 0.4
        request.maximumObservations = 8

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let found = (request.results as? [VNRectangleObservation]) ?? []
        let candidates = found.compactMap { observation -> (quad: Quadrilateral, score: CGFloat)? in
            let quad = Self.pixelQuad(from: observation, width: width, height: height)
            let score = Self.score(quad, imageSize: CGSize(width: width, height: height), confidence: CGFloat(observation.confidence))
            guard score > 0 else { return nil }
            return (quad, score)
        }
        return candidates.max(by: { $0.score < $1.score })?.quad
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

    private static func score(_ quad: Quadrilateral, imageSize: CGSize, confidence: CGFloat) -> CGFloat {
        let width = hypot(quad.topRight.x - quad.topLeft.x, quad.topRight.y - quad.topLeft.y)
        let height = hypot(quad.bottomLeft.x - quad.topLeft.x, quad.bottomLeft.y - quad.topLeft.y)
        guard width > 0, height > 0 else { return 0 }
        let aspect = width / height
        guard aspect >= 0.8, aspect <= 1.25 else { return 0 }
        let minDim = min(imageSize.width, imageSize.height)
        let sizeFraction = min(width, height) / minDim
        guard sizeFraction >= 0.35 else { return 0 }
        let squareness = 1 - abs(1 - aspect)
        return squareness * sizeFraction * (0.5 + confidence)
    }
}

protocol BoardLocalizer: Sendable {
    func detect(in buffer: CVPixelBuffer) async -> Quadrilateral?
}
