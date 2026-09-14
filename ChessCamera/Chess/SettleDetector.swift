import Foundation

struct SettleConfig: Sendable {
    var stableDuration: Duration = .milliseconds(600)
    /// Occupancy flicker of this many bits is ignored so a still board can settle.
    /// Must stay below quiet-move Hamming (2) or real moves never arm inference.
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

    func quietElapsed(at time: ContinuousClock.Instant) -> Duration {
        guard let lastChangeTime else { return .zero }
        return time - lastChangeTime
    }
}

/// Inter-frame jitter stays at 1 bit so flicker does not restart settle.
/// Captures are also 1 bit vs the committed mask, so arm `.disturbed` from
/// commit Hamming instead of waiting for a 2-bit transient (or a hand wave).
enum CommitRelativeMotion {
    static let maxInferHamming = 16

    static func arm(
        phase: SessionPhase,
        motion: BoardMotion,
        occupancy: Occupancy,
        commitHamming: Int
    ) -> BoardMotion {
        guard phase == .recording,
              (1...maxInferHamming).contains(commitHamming),
              case .stable = motion else {
            return motion
        }
        return .disturbed(since: occupancy)
    }
}
