import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation

struct WarpedBoard: Sendable {
    nonisolated(unsafe) var squareImage: CGImage
    var quad: Quadrilateral
}

enum BoardWarper {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func warp(_ buffer: CVPixelBuffer, quad: Quadrilateral, size: Int = 512) -> WarpedBoard? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let extent = ciImage.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        func ciPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: extent.height - p.y)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = ciPoint(quad.topLeft)
        filter.topRight = ciPoint(quad.topRight)
        filter.bottomRight = ciPoint(quad.bottomRight)
        filter.bottomLeft = ciPoint(quad.bottomLeft)

        guard let output = filter.outputImage else { return nil }
        let outExtent = output.extent
        guard outExtent.width > 1, outExtent.height > 1 else { return nil }

        let scaleX = CGFloat(size) / outExtent.width
        let scaleY = CGFloat(size) / outExtent.height
        let scaled = output
            .transformed(by: CGAffineTransform(translationX: -outExtent.minX, y: -outExtent.minY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let canvas = CGRect(x: 0, y: 0, width: size, height: size)
        guard let cgImage = context.createCGImage(scaled, from: canvas) else { return nil }
        return WarpedBoard(squareImage: cgImage, quad: quad)
    }
}
