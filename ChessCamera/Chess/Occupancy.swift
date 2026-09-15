import Foundation

struct Occupancy: Equatable, Sendable {
    var bits: UInt64 = 0

    static let allSquares = Occupancy(bits: .max)

    func occupied(_ square: ChessSquare) -> Bool {
        (bits & (UInt64(1) << square.bitIndex)) != 0
    }

    mutating func set(_ square: ChessSquare, occupied: Bool) {
        let mask: UInt64 = UInt64(1) << square.bitIndex
        if occupied { bits |= mask } else { bits &= ~mask }
    }

    func hammingDistance(to other: Occupancy) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }

    static func from(classes: [ChessSquare: PieceClass]) -> Occupancy {
        var occupancy = Occupancy()
        for (square, piece) in classes where piece != .empty {
            occupancy.set(square, occupied: true)
        }
        return occupancy
    }

    /// Occupied squares of a standard chess starting position (ranks 1, 2, 7, 8).
    static func standardStart() -> Occupancy {
        var occupancy = Occupancy()
        for file in 0..<8 {
            for rank in [0, 1, 6, 7] {
                occupancy.set(ChessSquare(file: file, rank: rank), occupied: true)
            }
        }
        return occupancy
    }

    static func fullStandardPawnsAndPieces() -> Occupancy {
        standardStart()
    }
}

/// Merge live occupancy with the last committed mask. Detections only fill
/// legal destination squares; empties only clear squares that some legal move
/// or fast reply actually vacates, and at most four new clears per frame so
/// rim misses do not look like extra captures.
struct OccupancyPrior: Equatable, Sendable {
    var fillable: Occupancy
    var clearable: Occupancy
    var maxNewClears: Int

    static let unconstrained = OccupancyPrior(
        fillable: .allSquares,
        clearable: .allSquares,
        maxNewClears: 64
    )

    init(fillable: Occupancy, clearable: Occupancy, maxNewClears: Int = 2) {
        self.fillable = fillable
        self.clearable = clearable
        self.maxNewClears = max(0, maxNewClears)
    }

    func apply(detected: Occupancy, previous: Occupancy) -> Occupancy {
        var result = previous
        result.bits |= detected.bits & ~previous.bits & fillable.bits
        let newClears = previous.bits & ~detected.bits & clearable.bits
        if newClears.nonzeroBitCount > maxNewClears {
            return result
        }
        result.bits &= ~newClears
        return result
    }
}
