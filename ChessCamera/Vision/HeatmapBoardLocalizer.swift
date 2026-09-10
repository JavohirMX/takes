import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation
import Vision

/// Core ML U-Net++ board localizer (Elucidation chessdetect). Optional — nil if model missing.
final class HeatmapBoardLocalizer: BoardLocalizer, @unchecked Sendable {
    private let model: MLModel
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    var minimumPeakScore: Float = 0.05
    var minimumSegmentationMean: Float = 0.08

    static func loadBundled() -> HeatmapBoardLocalizer? {
        let bundle = Bundle.main
        let url =
            bundle.url(forResource: "ChessboardUNet", withExtension: "mlmodelc")
            ?? bundle.url(forResource: "ChessboardUNet", withExtension: "mlpackage")
            ?? bundle.url(forResource: "ChessboardUNet", withExtension: "mlmodel")
        guard let url else { return nil }
        do {
            let compiled: URL
            if url.pathExtension == "mlmodel" || url.pathExtension == "mlpackage" {
                compiled = try MLModel.compileModel(at: url)
            } else {
                compiled = url
            }
            let mlModel = try MLModel(contentsOf: compiled)
            return HeatmapBoardLocalizer(model: mlModel)
        } catch {
            return nil
        }
    }

    init(model: MLModel) {
        self.model = model
    }

    func detect(in buffer: CVPixelBuffer) async -> Quadrilateral? {
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        guard width > 0, height > 0 else { return nil }
        let bufferSize = CGSize(width: width, height: height)
        let crop = HeatmapCornerDecode.centerCropSquare(srcSize: bufferSize)
        guard crop.width > 1, crop.height > 1 else { return nil }

        guard let input = makeInputArray(from: buffer, crop: crop) else { return nil }
        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: ["input_image": input])
        } catch {
            // Some conversions rename the input.
            guard let name = model.modelDescription.inputDescriptionsByName.keys.first,
                  let fallback = try? MLDictionaryFeatureProvider(dictionary: [name: input]) else {
                return nil
            }
            provider = fallback
        }

        let output: MLFeatureProvider
        do {
            output = try await model.prediction(from: provider)
        } catch {
            return nil
        }

        guard let corners = multiArray(namedHints: ["corners", "Identity", "var_0"], in: output),
              corners.shape.count >= 3 else {
            return nil
        }

        let (h, w, c, floats) = flattenCorners(corners)
        guard c == 4, h > 0, w > 0 else { return nil }

        if let seg = multiArray(namedHints: ["segmentation", "Identity_1", "var_1"], in: output) {
            let mean = meanValue(seg)
            if mean < minimumSegmentationMean { return nil }
        }

        let peaks = HeatmapCornerDecode.argmaxPeaks(corners: floats, height: h, width: w, channels: c)
        return HeatmapCornerDecode.quadFromPeaks(
            peaks,
            cropRect: crop,
            bufferSize: bufferSize,
            minimumScore: minimumPeakScore
        )
    }

    private func makeInputArray(from buffer: CVPixelBuffer, crop: CGRect) -> MLMultiArray? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let cropped = ciImage.cropped(to: crop)
        let scaleX = CGFloat(HeatmapCornerDecode.modelSize) / crop.width
        let scaleY = CGFloat(HeatmapCornerDecode.modelSize) / crop.height
        let scaled = cropped
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let canvas = CGRect(
            x: 0,
            y: 0,
            width: HeatmapCornerDecode.modelSize,
            height: HeatmapCornerDecode.modelSize
        )
        guard let cgImage = context.createCGImage(scaled, from: canvas) else { return nil }

        let size = HeatmapCornerDecode.modelSize
        guard let array = try? MLMultiArray(shape: [1, size as NSNumber, size as NSNumber, 3], dataType: .float32) else {
            return nil
        }
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bytesPerRow = cgImage.bytesPerRow
        let bpp = max(cgImage.bitsPerPixel / 8, 1)
        for y in 0..<size {
            for x in 0..<size {
                let o = y * bytesPerRow + x * bpp
                let r = Float(ptr[o]) / 255
                let g = Float(ptr[min(o + 1, bytesPerRow * size - 1)]) / 255
                let b = Float(ptr[min(o + 2, bytesPerRow * size - 1)]) / 255
                let base = (y * size + x) * 3
                array[base] = NSNumber(value: r)
                array[base + 1] = NSNumber(value: g)
                array[base + 2] = NSNumber(value: b)
            }
        }
        return array
    }

    private func multiArray(namedHints: [String], in provider: MLFeatureProvider) -> MLMultiArray? {
        for name in namedHints {
            if let value = provider.featureValue(for: name)?.multiArrayValue {
                return value
            }
        }
        for name in provider.featureNames {
            if let value = provider.featureValue(for: name)?.multiArrayValue {
                let shape = value.shape.map(\.intValue)
                if shape.last == 4 || (shape.count >= 3 && shape[shape.count - 1] == 4) {
                    return value
                }
            }
        }
        for name in provider.featureNames {
            if let value = provider.featureValue(for: name)?.multiArrayValue {
                return value
            }
        }
        return nil
    }

    private func flattenCorners(_ array: MLMultiArray) -> (Int, Int, Int, [Float]) {
        let shape = array.shape.map(\.intValue)
        // Possible layouts: [1,H,W,4], [H,W,4], [1,4,H,W]
        if shape.count == 4, shape[3] == 4 {
            let h = shape[1]
            let w = shape[2]
            let c = 4
            var out = [Float](repeating: 0, count: h * w * c)
            for y in 0..<h {
                for x in 0..<w {
                    for ch in 0..<c {
                        out[(y * w + x) * c + ch] = array[[0, y, x, ch] as [NSNumber]].floatValue
                    }
                }
            }
            return (h, w, c, out)
        }
        if shape.count == 3, shape[2] == 4 {
            let h = shape[0]
            let w = shape[1]
            let c = 4
            var out = [Float](repeating: 0, count: h * w * c)
            for y in 0..<h {
                for x in 0..<w {
                    for ch in 0..<c {
                        out[(y * w + x) * c + ch] = array[[y, x, ch] as [NSNumber]].floatValue
                    }
                }
            }
            return (h, w, c, out)
        }
        if shape.count == 4, shape[1] == 4 {
            let c = 4
            let h = shape[2]
            let w = shape[3]
            var out = [Float](repeating: 0, count: h * w * c)
            for y in 0..<h {
                for x in 0..<w {
                    for ch in 0..<c {
                        out[(y * w + x) * c + ch] = array[[0, ch, y, x] as [NSNumber]].floatValue
                    }
                }
            }
            return (h, w, c, out)
        }
        return (0, 0, 0, [])
    }

    private func meanValue(_ array: MLMultiArray) -> Float {
        let count = array.count
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += array[i].floatValue
        }
        return sum / Float(count)
    }
}
