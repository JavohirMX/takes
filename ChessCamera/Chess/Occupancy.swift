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
/// or fast reply actually vacates. Too many new clears, or fills with no
/// matching clear, keep the previous mask so ghost destinations cannot stick.
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
        let newFills = detected.bits & ~previous.bits & fillable.bits
        let newClears = previous.bits & ~detected.bits & clearable.bits
        if newClears.nonzeroBitCount > maxNewClears {
            return previous
        }
        // Ghost destinations with origins still occupied. Captures are 1+
        // clears and 0 extra fills, so they still apply.
        if newFills != 0 && newClears == 0 {
            return previous
        }
        var result = previous
        result.bits |= newFills
        result.bits &= ~newClears
        return result
    }
}

/// Combine YOLO occupancy with fingerprint change detection.
enum OccupancyFusion {
    /// Prefer agreement. Flagged YOLO-miss → fingerprint. Unflagged → YOLO.
    /// Flagged conflict (both sides disagree with previous differently) → previous.
    static func combine(
        previous: Occupancy,
        yolo: Occupancy,
        fingerprint: Occupancy,
        changed: Occupancy
    ) -> Occupancy {
        var fused = Occupancy()
        for file in 0..<8 {
            for rank in 0..<8 {
                let square = ChessSquare(file: file, rank: rank)
                let yoloBit = yolo.occupied(square)
                let fingerprintBit = fingerprint.occupied(square)
                let previousBit = previous.occupied(square)
                let flagged = changed.occupied(square)
                let bit: Bool
                if yoloBit == fingerprintBit {
                    bit = yoloBit
                } else if flagged, yoloBit == previousBit {
                    bit = fingerprintBit
                } else if !flagged {
                    bit = yoloBit
                } else {
                    bit = previousBit
                }
                fused.set(square, occupied: bit)
            }
        }
        return fused
    }
}

/// Freeze only illegal-sized fused deltas. High fingerprint Δ means lighting
/// chaos — ignore photometry in the pipeline; do not freeze occupancy.
enum OccupancyNoiseGate {
    /// Fingerprint change count at or above this discards fingerprint for fusion.
    static let maxFingerprintChanges = 6
    /// Fused Hamming vs committed above this freezes (quiet=2, castle/capture≤4).
    static let maxFusedHamming = 4

    static func shouldFreeze(fusedHamming: Int) -> Bool {
        fusedHamming > maxFusedHamming
    }

    static func fingerprintUnusable(changedCount: Int) -> Bool {
        changedCount >= maxFingerprintChanges
    }
}
