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

    /// Treat `occupancy` as already quiet so the first ham-0 frames are stable.
    mutating func seed(occupancy: Occupancy, at time: ContinuousClock.Instant) {
        lastOccupancy = occupancy
        lastChangeTime = time - config.stableDuration
    }

    func quietElapsed(at time: ContinuousClock.Instant) -> Duration {
        guard let lastChangeTime else { return .zero }
        return time - lastChangeTime
    }
}

/// Inter-frame jitter stays at 1 bit so flicker does not restart settle.
/// Captures are also 1 bit vs the committed mask, so infer from a stable
/// recording frame instead of pretending the board is still moving.
enum CommitRelativeMotion {
    static let maxInferHamming = 16
}

enum LiveSettleAction: Equatable, Sendable {
    /// Hands on the board, Hamming 0, or not yet quiet. Do not infer.
    case wait
    /// Settled occupancy differs from commit; run move inference.
    case infer(Occupancy)
    /// Same unmatched bits as a previous illegal settle; stay recording.
    case skipIgnored
}

enum LiveSettleDecision {
    static let ignoredTTL: Duration = .seconds(2)

    static func action(
        phase: SessionPhase,
        settleMotion: BoardMotion,
        occupancy: Occupancy,
        commitHamming: Int,
        ignored: Occupancy?,
        ignoredAt: ContinuousClock.Instant? = nil,
        now: ContinuousClock.Instant? = nil
    ) -> LiveSettleAction {
        if let ignored, occupancy == ignored {
            let expired = if let ignoredAt, let now {
                now - ignoredAt >= ignoredTTL
            } else {
                false
            }
            if !expired {
                return .skipIgnored
            }
        }
        guard (1...CommitRelativeMotion.maxInferHamming).contains(commitHamming) else {
            return .wait
        }
        switch phase {
        case .recording, .disturbed:
            guard case .stable(let occ) = settleMotion else { return .wait }
            return .infer(occ)
        default:
            return .wait
        }
    }
}
