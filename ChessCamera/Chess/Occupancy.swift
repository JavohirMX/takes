import Foundation

struct Occupancy: Equatable, Sendable {
    var bits: UInt64 = 0

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
