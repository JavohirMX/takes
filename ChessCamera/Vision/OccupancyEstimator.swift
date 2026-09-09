import CoreGraphics
import Foundation

struct SquareFingerprint: Equatable, Sendable {
    var mean: Double
    var variance: Double

    static func make(_ image: CGImage) -> SquareFingerprint {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return SquareFingerprint(mean: 0, variance: 0)
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return SquareFingerprint(mean: 0, variance: 0)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0.0
        var sumSq = 0.0
        var count = 0.0
        let step = max(1, min(width, height) / 16)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let i = y * bytesPerRow + x * bytesPerPixel
                let luma = 0.299 * Double(data[i]) + 0.587 * Double(data[i + 1]) + 0.114 * Double(data[i + 2])
                sum += luma
                sumSq += luma * luma
                count += 1
            }
        }
        guard count > 0 else { return SquareFingerprint(mean: 0, variance: 0) }
        let mean = sum / count
        let variance = max(0, sumSq / count - mean * mean)
        return SquareFingerprint(mean: mean, variance: variance)
    }

    static func average(_ items: [SquareFingerprint]) -> SquareFingerprint? {
        guard !items.isEmpty else { return nil }
        let mean = items.map(\.mean).reduce(0, +) / Double(items.count)
        let variance = items.map(\.variance).reduce(0, +) / Double(items.count)
        return SquareFingerprint(mean: mean, variance: variance)
    }
}

protocol OccupancyEstimator: Sendable {
    func occupancy(crops: [SquareCrop], classes: [ChessSquare: PieceClass]?) -> Occupancy
}

struct HeuristicOccupancyEstimator: OccupancyEstimator, Sendable {
    var emptyBaseline: [ChessSquare: SquareFingerprint] = [:]
    var globalEmpty: SquareFingerprint?
    var varianceThreshold: Double = 80
    var meanDeltaThreshold: Double = 18

    mutating func captureBaselines(crops: [SquareCrop], occupied: Occupancy) {
        var empties: [SquareFingerprint] = []
        for crop in crops {
            let fingerprint = SquareFingerprint.make(crop.image)
            if !occupied.occupied(crop.square) {
                emptyBaseline[crop.square] = fingerprint
                empties.append(fingerprint)
            }
        }
        globalEmpty = SquareFingerprint.average(empties)
    }

    func occupancy(crops: [SquareCrop], classes: [ChessSquare: PieceClass]?) -> Occupancy {
        var result = Occupancy()
        if let classes, !classes.isEmpty {
            for crop in crops {
                if let piece = classes[crop.square], piece != .empty {
                    result.set(crop.square, occupied: true)
                }
            }
            return result
        }

        for crop in crops {
            if isOccupied(SquareFingerprint.make(crop.image), square: crop.square) {
                result.set(crop.square, occupied: true)
            }
        }
        return result
    }

    func isOccupied(_ fingerprint: SquareFingerprint, square: ChessSquare) -> Bool {
        let baseline = emptyBaseline[square] ?? globalEmpty
        if let baseline {
            let meanDiff = abs(fingerprint.mean - baseline.mean)
            let extraVariance = fingerprint.variance - baseline.variance
            return meanDiff > meanDeltaThreshold || extraVariance > 60 || fingerprint.variance > max(varianceThreshold, baseline.variance * 3)
        }
        return fingerprint.variance > varianceThreshold
    }
}

enum OccupancyHeuristic {
    static func isOccupied(
        fingerprint: SquareFingerprint,
        baseline: SquareFingerprint?,
        varianceThreshold: Double = 80,
        meanDeltaThreshold: Double = 18
    ) -> Bool {
        if let baseline {
            let meanDiff = abs(fingerprint.mean - baseline.mean)
            let extraVariance = fingerprint.variance - baseline.variance
            return meanDiff > meanDeltaThreshold
                || extraVariance > 60
                || fingerprint.variance > max(varianceThreshold, baseline.variance * 3)
        }
        return fingerprint.variance > varianceThreshold
    }
}
