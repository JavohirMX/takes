import CoreGraphics
import Foundation

/// OpenCV imgproc/calib3d wrapper. The rest of the app talks only to `RefinedBoardGrid`.
enum OpenCVGridRefiner {
    enum Source: Sendable, Equatable {
        case chessboardCorners
        case hough
    }

    struct RefineResult: Sendable {
        var grid: RefinedBoardGrid
        var source: Source
    }

    static func refine(_ image: CGImage) -> RefinedBoardGrid? {
        refineDetailed(image)?.grid
    }

    /// Prefer `findChessboardCorners`; fall back to Hough lattice.
    static func refineDetailed(_ image: CGImage) -> RefineResult? {
        let size = CGFloat(min(image.width, image.height))
        if let corners = OpenCVGridRefinerBridge.innerChessboardCorners(in: image),
           let ordered = orderInner7x7(corners.map(\.cgPointValue)),
           let lattice = extrapolate9x9(fromInner7x7: ordered) {
            let grid = RefinedBoardGrid(imageSize: size, points: lattice)
            if grid.isMonotonic {
                return RefineResult(grid: grid, source: .chessboardCorners)
            }
        }
        if let hough = houghLattice(from: OpenCVGridRefinerBridge.houghLineParameters(in: image), imageSize: size) {
            let grid = RefinedBoardGrid(imageSize: size, points: hough)
            if grid.isMonotonic {
                return RefineResult(grid: grid, source: .hough)
            }
        }
        return nil
    }

    static func extrapolate9x9(fromInner7x7 corners: [CGPoint]) -> [CGPoint]? {
        guard corners.count == 49 else { return nil }
        func inner(_ row: Int, _ col: Int) -> CGPoint { corners[row * 7 + col] }
        var rows7x9: [[CGPoint]] = []
        rows7x9.reserveCapacity(7)
        for row in 0..<7 {
            let pts = (0..<7).map { inner(row, $0) }
            guard let extended = extendTo9(pts) else { return nil }
            rows7x9.append(extended)
        }
        var grid = [CGPoint](repeating: .zero, count: RefinedBoardGrid.pointCount)
        for col in 0..<9 {
            let column = (0..<7).map { rows7x9[$0][col] }
            guard let extended = extendTo9(column) else { return nil }
            for row in 0..<9 {
                grid[row * 9 + col] = extended[row]
            }
        }
        return grid
    }

    static func cluster(rhos: [Float], expected: Int, imageSize: Float) -> [Float]? {
        guard !rhos.isEmpty else { return nil }
        let sorted = rhos.sorted()
        let minGap = imageSize / 16
        var clusters: [[Float]] = []
        for value in sorted {
            if var last = clusters.last, let mean = average(last), abs(value - mean) < minGap {
                last.append(value)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append([value])
            }
        }
        var means = clusters.map { average($0) ?? 0 }.sorted()
        means = means.filter { $0 >= -imageSize * 0.05 && $0 <= imageSize * 1.05 }
        if means.count == expected { return means }
        if means.count > expected {
            return bestWindow(means, count: expected)
        }
        return nil
    }

    static func orderInner7x7(_ corners: [CGPoint]) -> [CGPoint]? {
        guard corners.count == 49 else { return nil }
        let byY = corners.sorted { $0.y < $1.y }
        var ordered: [CGPoint] = []
        ordered.reserveCapacity(49)
        for row in 0..<7 {
            let slice = byY[(row * 7)..<((row + 1) * 7)].sorted { $0.x < $1.x }
            ordered.append(contentsOf: slice)
        }
        return ordered
    }

    private static func extendTo9(_ seven: [CGPoint]) -> [CGPoint]? {
        guard seven.count == 7 else { return nil }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        for i in 0..<6 {
            dx += seven[i + 1].x - seven[i].x
            dy += seven[i + 1].y - seven[i].y
        }
        dx /= 6
        dy /= 6
        let start = CGPoint(x: seven[0].x - dx, y: seven[0].y - dy)
        let end = CGPoint(x: seven[6].x + dx, y: seven[6].y + dy)
        return [start] + seven + [end]
    }

    private static func houghLattice(from packed: [NSNumber], imageSize: CGFloat) -> [CGPoint]? {
        guard packed.count >= 4, packed.count % 2 == 0 else { return nil }
        var horizontalRho: [Float] = []
        var verticalRho: [Float] = []
        var index = 0
        while index + 1 < packed.count {
            let rho = packed[index].floatValue
            let theta = packed[index + 1].floatValue
            index += 2
            let angle = CGFloat(theta)
            if abs(angle - .pi / 2) < 0.25 {
                horizontalRho.append(abs(rho))
            } else if angle < 0.25 || abs(angle - .pi) < 0.25 {
                verticalRho.append(abs(rho))
            }
        }
        let size = Float(imageSize)
        guard let xs = cluster(rhos: verticalRho, expected: 9, imageSize: size),
              let ys = cluster(rhos: horizontalRho, expected: 9, imageSize: size) else {
            return nil
        }
        var points: [CGPoint] = []
        points.reserveCapacity(81)
        for row in 0..<9 {
            for col in 0..<9 {
                points.append(CGPoint(x: CGFloat(xs[col]), y: CGFloat(ys[row])))
            }
        }
        return points
    }

    private static func average(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func bestWindow(_ means: [Float], count: Int) -> [Float]? {
        guard means.count >= count else { return nil }
        var bestStart = 0
        var bestScore = Float.greatestFiniteMagnitude
        for start in 0...(means.count - count) {
            let window = Array(means[start..<(start + count)])
            let span = window[count - 1] - window[0]
            guard span > 0 else { continue }
            let expectedStep = span / Float(count - 1)
            var score: Float = 0
            for i in 0..<(count - 1) {
                let delta = (window[i + 1] - window[i]) - expectedStep
                score += delta * delta
            }
            if score < bestScore {
                bestScore = score
                bestStart = start
            }
        }
        return Array(means[bestStart..<(bestStart + count)])
    }
}
