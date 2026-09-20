import Foundation
import Observation

enum ClockSide: Equatable, Sendable {
    case white
    case black
}

enum FlaggedSide: Equatable, Sendable {
    case white
    case black
}

/// Dual Fischer clocks for casual timed OTB games.
@Observable
final class GameClockController {
    private(set) var whiteRemaining: TimeInterval = 0
    private(set) var blackRemaining: TimeInterval = 0
    private(set) var isRunning = false
    /// False when the Off preset is active — ticks are no-ops.
    private(set) var isEnabled = false
    private(set) var activeSide: ClockSide?
    private(set) var increment: TimeInterval = 0
    private(set) var base: TimeInterval = 0

    /// Configure both clocks to `base` with Fischer `increment` after each commit.
    /// Pass `base <= 0` to disable (Off).
    func configure(base: TimeInterval, increment: TimeInterval) {
        guard base > 0 else {
            configureOff()
            return
        }
        self.base = base
        self.increment = max(0, increment)
        whiteRemaining = base
        blackRemaining = base
        isEnabled = true
        isRunning = false
        activeSide = nil
    }

    func configureOff() {
        base = 0
        increment = 0
        whiteRemaining = 0
        blackRemaining = 0
        isEnabled = false
        isRunning = false
        activeSide = nil
    }

    /// Restore remaining times (e.g. continuing a saved game) while keeping the control parameters.
    func restore(
        white: TimeInterval,
        black: TimeInterval,
        base: TimeInterval,
        increment: TimeInterval
    ) {
        guard base > 0 else {
            configureOff()
            return
        }
        self.base = base
        self.increment = max(0, increment)
        whiteRemaining = max(0, white)
        blackRemaining = max(0, black)
        isEnabled = true
        isRunning = false
        activeSide = nil
    }

    func startIfNeeded(side: ClockSide) {
        guard isEnabled else { return }
        activeSide = side
        isRunning = true
    }

    /// Update which side is to move without necessarily starting the clock.
    func setActiveSide(_ side: ClockSide) {
        guard isEnabled else { return }
        activeSide = side
    }

    func pause() {
        isRunning = false
    }

    /// After a side commits a move: add Fischer increment to the mover, then run the new side.
    func onMoveCommitted(newSide: ClockSide) {
        guard isEnabled else { return }
        let mover: ClockSide = newSide == .white ? .black : .white
        switch mover {
        case .white: whiteRemaining += increment
        case .black: blackRemaining += increment
        }
        activeSide = newSide
        isRunning = true
    }

    /// Deduct `delta` from the active side. Returns the flagged side when time hits zero.
    func tick(delta: TimeInterval) -> FlaggedSide? {
        guard isEnabled, isRunning, let side = activeSide, delta > 0 else { return nil }
        switch side {
        case .white:
            whiteRemaining = max(0, whiteRemaining - delta)
            if whiteRemaining <= 0 {
                isRunning = false
                return .white
            }
        case .black:
            blackRemaining = max(0, blackRemaining - delta)
            if blackRemaining <= 0 {
                isRunning = false
                return .black
            }
        }
        return nil
    }

    static func format(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Wall-clock think time for the side to move. Independent of Fischer clocks.
/// Pause with the same session gates as clocks so hands-on-board time is excluded.
@Observable
final class MoveThinkTimer {
    private(set) var currentThinkElapsed: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var thinkingSide: ClockSide?

    func startThink(for side: ClockSide) {
        thinkingSide = side
        currentThinkElapsed = 0
        isRunning = true
    }

    func pauseThink() {
        isRunning = false
    }

    func resumeThinkIfNeeded() {
        guard thinkingSide != nil else { return }
        isRunning = true
    }

    func tick(delta: TimeInterval) {
        guard isRunning, delta > 0 else { return }
        currentThinkElapsed += delta
    }

    /// Returns elapsed think time for the completed ply and clears the accumulator.
    @discardableResult
    func consumeThinkTime() -> TimeInterval {
        let elapsed = currentThinkElapsed
        currentThinkElapsed = 0
        isRunning = false
        return elapsed
    }

    func reset() {
        currentThinkElapsed = 0
        isRunning = false
        thinkingSide = nil
    }

    /// Compact UI label: `12.4s` under 60s, else `m:ss` / `h:mm:ss`.
    static func formatCompact(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        if value < 60 {
            let tenths = Int((value * 10).rounded(.down))
            let whole = tenths / 10
            let frac = tenths % 10
            if frac == 0 {
                return "\(whole)s"
            }
            return "\(whole).\(frac)s"
        }
        return GameClockController.format(remaining: value)
    }

    /// PGN `%emt` body as `H:MM:SS`.
    static func formatEMT(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
}
