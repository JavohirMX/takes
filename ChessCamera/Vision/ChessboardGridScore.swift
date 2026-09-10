import CoreGraphics
import Foundation

/// Occlusion-tolerant checkerboard prior on a perspective-normalized board image.
enum ChessboardGridScore {
    /// Returns 0...1-ish likeness. Higher = more chessboard-like.
    static func score(gray: GrayFrame) -> CGFloat {
        guard gray.width >= 16, gray.height >= 16 else { return 0 }
        let cells = cellMeans(gray: gray)
        let polarity = polarityScore(cells)
        let gutters = gutterScore(gray: gray)
        return min(1.5, polarity * 0.75 + gutters * 0.25)
    }

    static func score(cgImage: CGImage) -> CGFloat {
        guard let gray = GrayFrame.from(cgImage: cgImage) else { return 0 }
        return score(gray: gray)
    }

    /// Mean luma for each of 64 square centers (row-major, file 0..7 within rank).
    static func cellMeans(gray: GrayFrame) -> [Double] {
        var means = [Double](repeating: 0, count: 64)
        let patch = max(1, min(gray.width, gray.height) / 32)
        for rank in 0..<8 {
            for file in 0..<8 {
                let cx = Int(((Double(file) + 0.5) / 8.0) * Double(gray.width))
                let cy = Int(((Double(rank) + 0.5) / 8.0) * Double(gray.height))
                var sum = 0.0
                var count = 0.0
                for dy in -patch...patch {
                    for dx in -patch...patch {
                        sum += Double(gray[cx + dx, cy + dy])
                        count += 1
                    }
                }
                means[rank * 8 + file] = sum / max(count, 1)
            }
        }
        return means
    }

    /// Better of two checkerboard phases; trims the worst 25% cell errors for occlusion.
    static func polarityScore(_ cells: [Double]) -> CGFloat {
        guard cells.count == 64 else { return 0 }
        return max(phaseScore(cells, phase: 0), phaseScore(cells, phase: 1))
    }

    private static func phaseScore(_ cells: [Double], phase: Int) -> CGFloat {
        var dark: [Double] = []
        var light: [Double] = []
        dark.reserveCapacity(32)
        light.reserveCapacity(32)
        for i in 0..<64 {
            let file = i % 8
            let rank = i / 8
            let expectedDark = ((file + rank) % 2) == phase
            if expectedDark {
                dark.append(cells[i])
            } else {
                light.append(cells[i])
            }
        }
        let meanDark = trimmedMean(dark)
        let meanLight = trimmedMean(light)
        let separation = meanLight - meanDark
        guard separation > 1 else { return 0 }

        // Per-cell agreement with expected polarity vs midpoint; drop worst quartile.
        let mid = (meanDark + meanLight) * 0.5
        var agreements: [Double] = []
        agreements.reserveCapacity(64)
        for i in 0..<64 {
            let file = i % 8
            let rank = i / 8
            let expectedDark = ((file + rank) % 2) == phase
            let value = cells[i]
            let agree: Double
            if expectedDark {
                agree = mid - value
            } else {
                agree = value - mid
            }
            agreements.append(agree)
        }
        agreements.sort(by: >)
        let keep = max(1, (agreements.count * 3) / 4)
        let robust = agreements.prefix(keep).reduce(0, +) / Double(keep)
        // ~20 luma separation with strong agreement → ~1.0
        return CGFloat(max(0, min(1.2, robust / 25.0)))
    }

    private static func trimmedMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let drop = sorted.count / 8
        let slice = sorted.dropFirst(drop).dropLast(drop)
        let used = slice.isEmpty ? sorted : Array(slice)
        return used.reduce(0, +) / Double(used.count)
    }

    /// Soft file/rank gutter response after normalize (Hough-like, no raw-frame Hough).
    static func gutterScore(gray: GrayFrame) -> CGFloat {
        var scores: [Double] = []
        for i in 1..<8 {
            let x = Int((Double(i) / 8.0) * Double(gray.width))
            scores.append(columnEdge(gray: gray, x: x))
            let y = Int((Double(i) / 8.0) * Double(gray.height))
            scores.append(rowEdge(gray: gray, y: y))
        }
        let mean = scores.reduce(0, +) / Double(max(scores.count, 1))
        return CGFloat(max(0, min(1.2, mean / 40.0)))
    }

    private static func columnEdge(gray: GrayFrame, x: Int) -> Double {
        var sum = 0.0
        var count = 0.0
        let x0 = max(0, x - 1)
        let x1 = min(gray.width - 1, x + 1)
        for y in 0..<gray.height {
            sum += abs(Double(gray[x1, y]) - Double(gray[x0, y]))
            count += 1
        }
        return sum / max(count, 1)
    }

    private static func rowEdge(gray: GrayFrame, y: Int) -> Double {
        var sum = 0.0
        var count = 0.0
        let y0 = max(0, y - 1)
        let y1 = min(gray.height - 1, y + 1)
        for x in 0..<gray.width {
            sum += abs(Double(gray[x, y1]) - Double(gray[x, y0]))
            count += 1
        }
        return sum / max(count, 1)
    }
}
