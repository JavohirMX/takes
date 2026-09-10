import Foundation

struct SettleConfig: Sendable {
    var stableDuration: Duration = .milliseconds(600)
    /// Occupancy flicker of this many bits is ignored so a still board can settle.
    var maxHammingJitter: Int = 1
}

enum BoardMotion: Equatable, Sendable {
    case stable(Occupancy)
    case disturbed(since: Occupancy)
}

struct SettleDetector: Sendable {
    var config: SettleConfig

    private var lastOccupancy: Occupancy?
    private var lastChangeTime: ContinuousClock.Instant?

    init(config: SettleConfig = SettleConfig()) {
        self.config = config
    }

    mutating func ingest(_ occupancy: Occupancy, at time: ContinuousClock.Instant) -> BoardMotion {
        if let lastOccupancy {
            let distance = lastOccupancy.hammingDistance(to: occupancy)
            if distance > config.maxHammingJitter {
                self.lastOccupancy = occupancy
                lastChangeTime = time
                return .disturbed(since: occupancy)
            }
        } else {
            lastOccupancy = occupancy
            lastChangeTime = time
            return .disturbed(since: occupancy)
        }

        lastOccupancy = occupancy
        let elapsed = time - (lastChangeTime ?? time)
        if elapsed >= config.stableDuration {
            return .stable(occupancy)
        }
        return .disturbed(since: occupancy)
    }
}
