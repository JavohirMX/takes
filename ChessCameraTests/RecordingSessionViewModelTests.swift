import ChessKit
import Testing
@testable import ChessCamera

@Suite("RecordingSessionViewModel tests")
struct RecordingSessionViewModelTests {
    @Test @MainActor
    func twoCommitsUpdateLastSANAndPGN() throws {
        let model = RecordingSessionViewModel()
        model.startRecording()

        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)
        #expect(model.lastSAN == "1. e4")
        #expect(model.committedSANs.count == 1)
        #expect(model.committedPlyCount == 1)

        let e5 = try #require(Move(san: "e5", position: model.engine.board.position))
        try model.commit(move: e5)
        #expect(model.lastSAN == "1... e5")
        #expect(model.committedSANs.count == 2)
        #expect(model.committedPlyCount == 2)
        #expect(model.engine.pgn.contains("e4"))
        #expect(model.engine.pgn.contains("e5"))
    }

    @Test @MainActor
    func undoRestoresMirroredNotation() throws {
        let model = RecordingSessionViewModel()
        model.startRecording()
        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)
        let e5 = try #require(Move(san: "e5", position: model.engine.board.position))
        try model.commit(move: e5)
        model.undoLast()
        #expect(model.lastSAN == "1. e4")
        #expect(model.committedSANs.count == 1)
    }

    @Test @MainActor
    func autoResumeTransitionsBackToRecordingWhenEnabled() async throws {
        let saved = AutoResumeSettings.enabled
        defer { AutoResumeSettings.enabled = saved }

        AutoResumeSettings.enabled = true
        let model = RecordingSessionViewModel()
        model.autoResumeDelayMilliseconds = 50
        model.phase = .awaitingEdit

        model.scheduleAutoResumeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))

        #expect(model.phase == .recording)
    }

    @Test @MainActor
    func autoResumeCancelledIfUserBeginsEdit() async throws {
        let saved = AutoResumeSettings.enabled
        defer { AutoResumeSettings.enabled = saved }

        AutoResumeSettings.enabled = true
        let model = RecordingSessionViewModel()
        model.autoResumeDelayMilliseconds = 80
        model.phase = .awaitingEdit

        model.scheduleAutoResumeIfNeeded()
        model.beginEdit(replacingLast: false)

        try await Task.sleep(for: .milliseconds(120))
        #expect(model.phase == .awaitingEdit)
        #expect(model.showEditSheet == true)
    }

    @Test @MainActor
    func autoResumeDoesNotTriggerWhenDisabled() async throws {
        let saved = AutoResumeSettings.enabled
        defer { AutoResumeSettings.enabled = saved }

        AutoResumeSettings.enabled = false
        let model = RecordingSessionViewModel()
        model.autoResumeDelayMilliseconds = 50
        model.phase = .awaitingEdit

        model.scheduleAutoResumeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))

        #expect(model.phase == .awaitingEdit)
    }

    @Test @MainActor
    func liveAnalysisScheduledOnStartRecordingWhenEnabled() async throws {
        let saved = AnalysisSettings.liveHintsEnabled
        defer { AnalysisSettings.liveHintsEnabled = saved }

        AnalysisSettings.liveHintsEnabled = true
        let model = RecordingSessionViewModel()
        model.startRecording()

        // Give the analysis task time to initiate/run
        for _ in 0..<30 {
            if model.liveAnalysis != nil || model.liveAnalysisMessage != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(model.liveAnalysis != nil || model.liveAnalysisMessage != nil)
    }

    @Test @MainActor
    func liveAnalysisNotScheduledWhenDisabled() async throws {
        let saved = AnalysisSettings.liveHintsEnabled
        defer { AnalysisSettings.liveHintsEnabled = saved }

        AnalysisSettings.liveHintsEnabled = false
        let model = RecordingSessionViewModel()
        model.startRecording()

        try await Task.sleep(for: .milliseconds(100))
        #expect(model.liveAnalysis == nil)
        #expect(model.liveAnalysisMessage == nil)
    }

    @Test @MainActor
    func clearLiveAnalysisClearsState() async throws {
        let model = RecordingSessionViewModel()
        model.liveAnalysis = PositionAnalysis(
            fen: FenCodec.standard,
            score: .centipawns(20),
            bestMoveUCI: "e2e4",
            bestArrow: BoardArrow(from: ChessSquare(file: 4, rank: 1), to: ChessSquare(file: 4, rank: 3)),
            pvUCI: ["e2e4"],
            depth: 10
        )
        model.liveAnalysisMessage = "Calculating"

        model.clearLiveAnalysis()
        #expect(model.liveAnalysis == nil)
        #expect(model.liveAnalysisMessage == nil)
    }

    @Test @MainActor
    func savedRecordReturnsNilWhenZeroMoves() {
        let model = RecordingSessionViewModel()
        #expect(model.savedRecordIfNeeded() == nil)
    }

    @Test @MainActor
    func savedRecordPersistsAndUpdatesAcrossMoves() throws {
        let model = RecordingSessionViewModel()
        model.startRecording()

        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)

        let record1 = try #require(model.savedRecordIfNeeded())
        #expect(record1.pgn.contains("e4"))
        #expect(!record1.pgn.contains("e5"))

        let e5 = try #require(Move(san: "e5", position: model.engine.board.position))
        try model.commit(move: e5)

        let record2 = try #require(model.savedRecordIfNeeded())
        #expect(record2 === record1)
        #expect(record2.pgn.contains("e4"))
        #expect(record2.pgn.contains("e5"))
    }

    @Test @MainActor
    func undoLastResetsSavedRecordDraft() throws {
        let model = RecordingSessionViewModel()
        model.startRecording()

        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)
        _ = model.savedRecordIfNeeded()
        #expect(model.savedRecord != nil)

        model.undoLast()
        #expect(model.savedRecord == nil)
    }
}
