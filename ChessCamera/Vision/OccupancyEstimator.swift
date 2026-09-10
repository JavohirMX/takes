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
    private var fingerprints: [ChessSquare: SquareFingerprint] = [:]

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

    mutating func snapshot(crops: [SquareCrop]) {
        fingerprints = [:]
        for crop in crops {
            fingerprints[crop.square] = SquareFingerprint.make(crop.image)
        }
    }

    var hasSnapshot: Bool { !fingerprints.isEmpty }

    /// Known game occupancy, updated only on squares that changed vs the last snapshot.
    /// Independent empty/occupied classification is too noisy to ever match a legal move.
    func occupancyApplyingChanges(crops: [SquareCrop], previous: Occupancy) -> Occupancy {
        guard hasSnapshot, !crops.isEmpty else {
            return occupancy(crops: crops, classes: nil)
        }

        var scores = [Double](repeating: 0, count: crops.count)
        var current = [SquareFingerprint?](repeating: nil, count: crops.count)
        for (index, crop) in crops.enumerated() {
            let fingerprint = SquareFingerprint.make(crop.image)
            current[index] = fingerprint
            if let baseline = fingerprints[crop.square] {
                scores[index] = SquareChangeDetector.score(current: fingerprint, baseline: baseline)
            }
        }

        let changed = SquareChangeDetector.changedMask(scores: scores)
        var result = previous
        for (index, crop) in crops.enumerated() where changed[index] {
            guard let fingerprint = current[index],
                  let baseline = fingerprints[crop.square] else { continue }
            if previous.occupied(crop.square) {
                let emptied = fingerprint.variance < baseline.variance * 0.55
                result.set(crop.square, occupied: !emptied)
            } else {
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

enum SquareChangeDetector {
    static func score(current: SquareFingerprint, baseline: SquareFingerprint) -> Double {
        abs(current.mean - baseline.mean) + 0.15 * abs(current.variance - baseline.variance)
    }

    /// Lighting-robust outliers: a square changed if it moved more than the board-wide median.
    static func changedMask(scores: [Double], absoluteMin: Double = 14, k: Double = 2.2) -> [Bool] {
        guard !scores.isEmpty else { return [] }
        let sorted = scores.sorted()
        let median = sorted[sorted.count / 2]
        let deviations = scores.map { abs($0 - median) }.sorted()
        let mad = deviations[deviations.count / 2]
        let threshold = max(absoluteMin, median + k * max(mad, 4))
        return scores.map { $0 >= threshold && $0 >= absoluteMin }
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
