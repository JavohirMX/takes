import CoreGraphics
import Foundation

/// Pure Studio refine / weak-track policy (unit-testable without camera frames).
enum BoardStudioRefinePolicy {
    static let stableSnapNeeded = 2
    static let weakTrackRecoverDuration: Duration = .seconds(1)
    static let weakTrackFreezeAfterFrames = 3

    /// Accumulate consecutive similar OpenCV snaps until settle.
    static func ingestStableSnap(
        pending: Quadrilateral?,
        hits: Int,
        candidate: Quadrilateral,
        imageSize: CGSize,
        similarityFraction: CGFloat = 0.1
    ) -> (pending: Quadrilateral, hits: Int, settled: Bool) {
        if let pending, pending.isSimilar(to: candidate, imageSize: imageSize, fraction: similarityFraction) {
            let nextHits = hits + 1
            return (candidate, nextHits, nextHits >= stableSnapNeeded)
        }
        return (candidate, 1, false)
    }

    /// Recapture corner templates only when the snap moved corners meaningfully.
    static func shouldRecaptureTemplates(
        previous: Quadrilateral?,
        snapped: Quadrilateral,
        imageSize: CGSize,
        similarityFraction: CGFloat = 0.1
    ) -> Bool {
        guard let previous, imageSize.width > 1, imageSize.height > 1 else { return true }
        return !previous.isSimilar(to: snapped, imageSize: imageSize, fraction: similarityFraction)
    }

    /// After brief weak updates, freeze; after recover duration, restart Vision.
    static func weakTrackAction(
        weakFrames: Int,
        weakStartedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        recoverAfter: Duration = weakTrackRecoverDuration
    ) -> WeakTrackAction {
        if weakFrames < weakTrackFreezeAfterFrames {
            return .updateQuad
        }
        if let weakStartedAt, now - weakStartedAt >= recoverAfter {
            return .restartVision
        }
        return .freeze
    }

    enum WeakTrackAction: Equatable {
        case updateQuad
        case freeze
        case restartVision
    }
}
