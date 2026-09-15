import Foundation

/// Per-square hysteresis so brief YOLO misses do not empty a piece.
/// Harder to clear an occupied square than to fill an empty one.
struct OccupancySmoother: Sendable {
    var emptyConfirmFrames: Int
    var fillConfirmFrames: Int

    private var sticky = Occupancy()
    private var emptyStreak = [UInt8](repeating: 0, count: 64)
    private var fillStreak = [UInt8](repeating: 0, count: 64)

    init(emptyConfirmFrames: Int = 3, fillConfirmFrames: Int = 2) {
        self.emptyConfirmFrames = max(1, emptyConfirmFrames)
        self.fillConfirmFrames = max(1, fillConfirmFrames)
    }

    mutating func ingest(_ occupancy: Occupancy) -> Occupancy {
        for index in 0..<64 {
            let mask = UInt64(1) << index
            let observed = occupancy.bits & mask != 0
            let held = sticky.bits & mask != 0
            if observed == held {
                emptyStreak[index] = 0
                fillStreak[index] = 0
                continue
            }
            if held {
                fillStreak[index] = 0
                emptyStreak[index] = emptyStreak[index] &+ 1
                if Int(emptyStreak[index]) >= emptyConfirmFrames {
                    sticky.bits &= ~mask
                    emptyStreak[index] = 0
                }
            } else {
                emptyStreak[index] = 0
                fillStreak[index] = fillStreak[index] &+ 1
                if Int(fillStreak[index]) >= fillConfirmFrames {
                    sticky.bits |= mask
                    fillStreak[index] = 0
                }
            }
        }
        return sticky
    }

    mutating func reset(seeding occupancy: Occupancy? = nil) {
        sticky = occupancy ?? Occupancy()
        emptyStreak = [UInt8](repeating: 0, count: 64)
        fillStreak = [UInt8](repeating: 0, count: 64)
    }
}
