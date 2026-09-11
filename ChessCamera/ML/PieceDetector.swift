import CoreGraphics
import CoreML
import Foundation
import Vision

protocol PieceDetector: Sendable {
    func detect(in warped: CGImage, orientation: BoardOrientation) async -> [ChessSquare: PieceClass]
    func detectBoxes(in image: CGImage) async -> [PieceDetection.Box]
}

enum PieceDetection {
    static let confidenceThreshold: Float = 0.25
    static let defaultImgsz = 640
    static let nmsIoUThreshold: CGFloat = 0.45
    static let maxOverlayBoxes = 32

    struct Candidate: Equatable, Sendable {
        var square: ChessSquare
        var piece: PieceClass
        var confidence: Float
    }

    struct Box: Equatable, Sendable, Identifiable {
        var id: Int
        var piece: PieceClass
        var confidence: Float
        /// Top-left origin, buffer / CGImage pixels.
        var bufferRect: CGRect

        var overlayLabel: String {
            let percent = Int((confidence * 100).rounded())
            return "\(piece.accessibilityName.localizedCapitalized) \(percent)%"
        }
    }

    /// Vision bounding box is normalized with origin at the bottom-left.
    /// Use the box bottom-center as the piece base on the square.
    static func imagePoint(
        fromVisionBox box: CGRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: box.midX * imageWidth,
            y: (1 - box.minY) * imageHeight
        )
    }

    /// Vision box → top-left CGImage / camera-buffer pixels.
    static func bufferRect(
        fromVisionBox box: CGRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: box.minX * imageWidth,
            y: (1 - box.maxY) * imageHeight,
            width: box.width * imageWidth,
            height: box.height * imageHeight
        )
    }

    /// YOLO xywh in `imgsz` letterboxed pixels (scale-fit) → image pixels.
    static func bufferRect(
        yoloCenterX cx: Float,
        centerY cy: Float,
        width boxW: Float,
        height boxH: Float,
        imgsz: Int,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGRect {
        let gain = min(CGFloat(imgsz) / imageWidth, CGFloat(imgsz) / imageHeight)
        guard gain > 0 else { return .zero }
        let padX = (CGFloat(imgsz) - imageWidth * gain) / 2
        let padY = (CGFloat(imgsz) - imageHeight * gain) / 2
        return CGRect(
            x: (CGFloat(cx) - CGFloat(boxW) / 2 - padX) / gain,
            y: (CGFloat(cy) - CGFloat(boxH) / 2 - padY) / gain,
            width: CGFloat(boxW) / gain,
            height: CGFloat(boxH) / gain
        )
    }

    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return 0 }
        let unionArea = a.width * a.height + b.width * b.height - inter.width * inter.height
        guard unionArea > 0 else { return 0 }
        return (inter.width * inter.height) / unionArea
    }

    static func nms(_ boxes: [Box], iouThreshold: CGFloat = nmsIoUThreshold, maxCount: Int = maxOverlayBoxes) -> [Box] {
        let sorted = boxes.sorted { $0.confidence > $1.confidence }
        var kept: [Box] = []
        kept.reserveCapacity(min(sorted.count, maxCount))
        for box in sorted {
            if kept.count >= maxCount { break }
            if kept.contains(where: { intersectionOverUnion($0.bufferRect, box.bufferRect) > iouThreshold }) {
                continue
            }
            kept.append(box)
        }
        return kept.enumerated().map { index, box in
            var copy = box
            copy.id = index
            return copy
        }
    }

    /// YOLO xywh is center format in `imgsz` pixels, top-left origin (same as CGImage).
    static func imagePoint(
        yoloCenterX cx: Float,
        centerY cy: Float,
        height h: Float,
        imgsz: Int,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGPoint {
        let scaleX = imageWidth / CGFloat(imgsz)
        let scaleY = imageHeight / CGFloat(imgsz)
        return CGPoint(
            x: CGFloat(cx) * scaleX,
            y: CGFloat(cy + h / 2) * scaleY
        )
    }

    static func candidate(
        yoloCenterX cx: Float,
        centerY cy: Float,
        height h: Float,
        classIndex: Int,
        confidence: Float,
        classNames: [String],
        imgsz: Int,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        orientation: BoardOrientation
    ) -> Candidate? {
        guard classIndex >= 0, classIndex < classNames.count,
              let piece = PieceClass.fromClassifierLabel(classNames[classIndex]),
              piece != .empty else { return nil }
        let point = imagePoint(
            yoloCenterX: cx,
            centerY: cy,
            height: h,
            imgsz: imgsz,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
        guard let square = GridSampler.square(
            containing: point,
            imageSize: min(imageWidth, imageHeight),
            orientation: orientation
        ) else { return nil }
        return Candidate(square: square, piece: piece, confidence: confidence)
    }

    /// Raw Ultralytics detect head: `[1, 4+nc, anchors]` or `[1, anchors, 4+nc]`.
    static func candidates(
        fromHead array: MLMultiArray,
        classNames: [String],
        imgsz: Int,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        orientation: BoardOrientation
    ) -> [Candidate] {
        let shape = array.shape.map(\.intValue)
        let nc = classNames.count
        let channels = 4 + nc
        guard shape.count == 3, shape[0] == 1 else { return [] }

        let channelFirst = shape[1] == channels
        let anchorCount = channelFirst ? shape[2] : shape[1]
        guard anchorCount > 0, (channelFirst ? shape[1] : shape[2]) == channels else { return [] }

        func value(channel: Int, anchor: Int) -> Float {
            if channelFirst {
                array[[0, channel, anchor] as [NSNumber]].floatValue
            } else {
                array[[0, anchor, channel] as [NSNumber]].floatValue
            }
        }

        var found: [Candidate] = []
        found.reserveCapacity(min(anchorCount, 64))
        for anchor in 0..<anchorCount {
            var bestClass = 0
            var bestScore = Float(-1)
            for cls in 0..<nc {
                let score = value(channel: 4 + cls, anchor: anchor)
                if score > bestScore {
                    bestScore = score
                    bestClass = cls
                }
            }
            guard bestScore >= confidenceThreshold else { continue }
            let cx = value(channel: 0, anchor: anchor)
            let cy = value(channel: 1, anchor: anchor)
            let boxH = value(channel: 3, anchor: anchor)
            if let candidate = candidate(
                yoloCenterX: cx,
                centerY: cy,
                height: boxH,
                classIndex: bestClass,
                confidence: bestScore,
                classNames: classNames,
                imgsz: imgsz,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                orientation: orientation
            ) {
                found.append(candidate)
            }
        }
        return found
    }

    /// Raw Ultralytics detect head → overlay boxes after greedy NMS.
    static func boxes(
        fromHead array: MLMultiArray,
        classNames: [String],
        imgsz: Int,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [Box] {
        let shape = array.shape.map(\.intValue)
        let nc = classNames.count
        let channels = 4 + nc
        guard shape.count == 3, shape[0] == 1 else { return [] }

        let channelFirst = shape[1] == channels
        let anchorCount = channelFirst ? shape[2] : shape[1]
        guard anchorCount > 0, (channelFirst ? shape[1] : shape[2]) == channels else { return [] }

        func value(channel: Int, anchor: Int) -> Float {
            if channelFirst {
                array[[0, channel, anchor] as [NSNumber]].floatValue
            } else {
                array[[0, anchor, channel] as [NSNumber]].floatValue
            }
        }

        var found: [Box] = []
        found.reserveCapacity(min(anchorCount, 64))
        for anchor in 0..<anchorCount {
            var bestClass = 0
            var bestScore = Float(-1)
            for cls in 0..<nc {
                let score = value(channel: 4 + cls, anchor: anchor)
                if score > bestScore {
                    bestScore = score
                    bestClass = cls
                }
            }
            guard bestScore >= confidenceThreshold,
                  bestClass >= 0, bestClass < classNames.count,
                  let piece = PieceClass.fromClassifierLabel(classNames[bestClass]),
                  piece != .empty else { continue }
            let cx = value(channel: 0, anchor: anchor)
            let cy = value(channel: 1, anchor: anchor)
            let boxW = value(channel: 2, anchor: anchor)
            let boxH = value(channel: 3, anchor: anchor)
            found.append(
                Box(
                    id: found.count,
                    piece: piece,
                    confidence: bestScore,
                    bufferRect: bufferRect(
                        yoloCenterX: cx,
                        centerY: cy,
                        width: boxW,
                        height: boxH,
                        imgsz: imgsz,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )
                )
            )
        }
        return nms(found)
    }

    /// Highest-confidence piece per square. Unoccupied squares are `.empty`.
    static func classes(from candidates: [Candidate]) -> [ChessSquare: PieceClass] {
        var best: [ChessSquare: Candidate] = [:]
        for candidate in candidates {
            guard candidate.piece != .empty,
                  candidate.confidence >= confidenceThreshold else { continue }
            if let existing = best[candidate.square], existing.confidence >= candidate.confidence {
                continue
            }
            best[candidate.square] = candidate
        }
        var classes: [ChessSquare: PieceClass] = [:]
        for file in 0..<8 {
            for rank in 0..<8 {
                classes[ChessSquare(file: file, rank: rank)] = .empty
            }
        }
        for (square, candidate) in best {
            classes[square] = candidate.piece
        }
        return classes
    }
}

/// Bundled Ultralytics YOLO detector (`ChessPieceYOLO.mlpackage`). Nil if the model is missing.
final class CoreMLPieceDetector: PieceDetector, @unchecked Sendable {
    private let vnModel: VNCoreMLModel
    private let classNames: [String]
    private let imgsz: Int

    static func loadBundled() -> CoreMLPieceDetector? {
        let bundle = Bundle.main
        let url =
            bundle.url(forResource: "ChessPieceYOLO", withExtension: "mlmodelc")
            ?? bundle.url(forResource: "ChessPieceYOLO", withExtension: "mlpackage")
            ?? bundle.url(forResource: "ChessPieceYOLO", withExtension: "mlmodel")
        guard let url else { return nil }
        do {
            let compiled: URL
            if url.pathExtension == "mlmodel" || url.pathExtension == "mlpackage" {
                compiled = try MLModel.compileModel(at: url)
            } else {
                compiled = url
            }
            let mlModel = try MLModel(contentsOf: compiled)
            let vnModel = try VNCoreMLModel(for: mlModel)
            return CoreMLPieceDetector(
                vnModel: vnModel,
                classNames: loadClassNames(bundle: bundle, model: mlModel),
                imgsz: loadImgsz(model: mlModel)
            )
        } catch {
            return nil
        }
    }

    init(vnModel: VNCoreMLModel, classNames: [String], imgsz: Int = PieceDetection.defaultImgsz) {
        self.vnModel = vnModel
        self.classNames = classNames
        self.imgsz = imgsz
    }

    func detect(in warped: CGImage, orientation: BoardOrientation) async -> [ChessSquare: PieceClass] {
        guard let request = runRequest(on: warped, scale: .scaleFill) else { return [:] }

        let width = CGFloat(warped.width)
        let height = CGFloat(warped.height)
        let candidates: [PieceDetection.Candidate]
        if let objects = request.results as? [VNRecognizedObjectObservation], !objects.isEmpty {
            candidates = candidatesFromVision(objects, width: width, height: height, orientation: orientation)
        } else if let features = request.results as? [VNCoreMLFeatureValueObservation],
                  let array = features.first(where: { $0.featureValue.multiArrayValue != nil })?
                  .featureValue.multiArrayValue {
            candidates = PieceDetection.candidates(
                fromHead: array,
                classNames: classNames,
                imgsz: imgsz,
                imageWidth: width,
                imageHeight: height,
                orientation: orientation
            )
        } else {
            return [:]
        }
        return PieceDetection.classes(from: candidates)
    }

    func detectBoxes(in image: CGImage) async -> [PieceDetection.Box] {
        guard let request = runRequest(on: image, scale: .scaleFit) else { return [] }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        if let objects = request.results as? [VNRecognizedObjectObservation], !objects.isEmpty {
            return boxesFromVision(objects, width: width, height: height)
        }
        if let features = request.results as? [VNCoreMLFeatureValueObservation],
           let array = features.first(where: { $0.featureValue.multiArrayValue != nil })?
           .featureValue.multiArrayValue {
            return PieceDetection.boxes(
                fromHead: array,
                classNames: classNames,
                imgsz: imgsz,
                imageWidth: width,
                imageHeight: height
            )
        }
        return []
    }

    private func runRequest(on image: CGImage, scale: VNImageCropAndScaleOption) -> VNCoreMLRequest? {
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = scale
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return request
        } catch {
            return nil
        }
    }

    private func candidatesFromVision(
        _ observations: [VNRecognizedObjectObservation],
        width: CGFloat,
        height: CGFloat,
        orientation: BoardOrientation
    ) -> [PieceDetection.Candidate] {
        var found: [PieceDetection.Candidate] = []
        found.reserveCapacity(observations.count)
        for observation in observations {
            guard let label = observation.labels.first,
                  let piece = PieceClass.fromClassifierLabel(label.identifier),
                  piece != .empty else { continue }
            let point = PieceDetection.imagePoint(
                fromVisionBox: observation.boundingBox,
                imageWidth: width,
                imageHeight: height
            )
            guard let square = GridSampler.square(
                containing: point,
                imageSize: min(width, height),
                orientation: orientation
            ) else { continue }
            found.append(
                PieceDetection.Candidate(
                    square: square,
                    piece: piece,
                    confidence: observation.confidence
                )
            )
        }
        return found
    }

    private func boxesFromVision(
        _ observations: [VNRecognizedObjectObservation],
        width: CGFloat,
        height: CGFloat
    ) -> [PieceDetection.Box] {
        var found: [PieceDetection.Box] = []
        found.reserveCapacity(min(observations.count, PieceDetection.maxOverlayBoxes))
        for (index, observation) in observations.enumerated() {
            guard observation.confidence >= PieceDetection.confidenceThreshold,
                  let label = observation.labels.first,
                  let piece = PieceClass.fromClassifierLabel(label.identifier),
                  piece != .empty else { continue }
            found.append(
                PieceDetection.Box(
                    id: index,
                    piece: piece,
                    confidence: observation.confidence,
                    bufferRect: PieceDetection.bufferRect(
                        fromVisionBox: observation.boundingBox,
                        imageWidth: width,
                        imageHeight: height
                    )
                )
            )
        }
        return PieceDetection.nms(found)
    }

    private static func loadClassNames(bundle: Bundle, model: MLModel) -> [String] {
        if let url = bundle.url(forResource: "ChessPieceYOLO", withExtension: "classes.txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let names = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !names.isEmpty { return names }
        }
        if let csv = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "class_names")] as? String {
            return csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
    }

    private static func loadImgsz(model: MLModel) -> Int {
        if let raw = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "imgsz")] as? String,
           let value = Int(raw) {
            return value
        }
        return PieceDetection.defaultImgsz
    }
}
