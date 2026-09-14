import Foundation

/// Majority-vote occupancy over a short frame window so 1-square flicker does not reset settle.
struct OccupancySmoother: Sendable {
    var windowSize: Int
    private var frames: [Occupancy] = []

    init(windowSize: Int = 3) {
        self.windowSize = windowSize
    }

    mutating func ingest(_ occupancy: Occupancy) -> Occupancy {
        frames.append(occupancy)
        if frames.count > windowSize {
            frames.removeFirst(frames.count - windowSize)
        }
        return majority()
    }

    mutating func reset(seeding occupancy: Occupancy? = nil) {
        if let occupancy {
            frames = [occupancy]
        } else {
            frames = []
        }
    }

    private func majority() -> Occupancy {
        guard let first = frames.first else { return Occupancy() }
        guard frames.count > 1 else { return first }

        let need = (frames.count + 1) / 2
        var bits: UInt64 = 0
        for index in 0..<64 {
            let mask = UInt64(1) << index
            var votes = 0
            for frame in frames where frame.bits & mask != 0 {
                votes += 1
            }
            if votes >= need {
                bits |= mask
            }
        }
        return Occupancy(bits: bits)
    }
}
