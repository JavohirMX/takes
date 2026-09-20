import Foundation

enum SessionPhase: Equatable, Sendable {
    case idle
    case importingVideo
    case boardStudio
    case pieceStudio
    case detectingBoard
    case calibratingCorners
    case confirmingStart
    case recording
    case disturbed
    case awaitingEdit
    case gameOver
    case replay
}

/// How `startRecording` should treat the game engine.
enum StartRecordingMode: Equatable, Sendable {
    /// Load `proposedFEN` / standard start (new game).
    case newGame
    /// Keep engine history; only re-seed vision baselines from engine occupancy.
    case continueOrResync
}

struct SessionReducer {
    static func next(
        phase: SessionPhase,
        motion: BoardMotion,
        inference: InferenceResult
    ) -> SessionPhase {
        switch phase {
        case .recording:
            if case .disturbed = motion {
                return .disturbed
            }
            if case .ambiguous = inference {
                return .awaitingEdit
            }
            return phase
        case .disturbed:
            guard case .stable = motion else { return .disturbed }
            switch inference {
            case .unique, .none, .illegal:
                // Illegal deltas soft-reject so one bad settle does not kill auto-capture.
                return .recording
            case .ambiguous:
                return .awaitingEdit
            }
        default:
            return phase
        }
    }
}
