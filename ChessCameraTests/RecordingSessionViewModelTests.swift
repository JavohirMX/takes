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
    func autoResumeStopsAfterConsecutiveRetryLimit() async throws {
        let saved = AutoResumeSettings.enabled
        defer { AutoResumeSettings.enabled = saved }

        AutoResumeSettings.enabled = true
        let model = RecordingSessionViewModel()
        model.autoResumeDelayMilliseconds = 20

        for retry in 1...4 {
            model.phase = .awaitingEdit
            model.scheduleAutoResumeIfNeeded()
            #expect(model.consecutiveAutoResumes == retry - 1)
            try await Task.sleep(for: .milliseconds(40))
            #expect(model.phase == .recording)
            #expect(model.consecutiveAutoResumes == retry)
        }

        // 5th attempt: consecutiveAutoResumes is 4 -> stops auto-resuming, stays in awaitingEdit
        model.phase = .awaitingEdit
        model.scheduleAutoResumeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        #expect(model.phase == .awaitingEdit)
        #expect(model.consecutiveAutoResumes == 4)

        // Committing a move resets the counter
        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)
        #expect(model.consecutiveAutoResumes == 0)
    }

    @Test @MainActor
    func liveAnalysisScheduledOnStartRecordingWhenEnabled() async throws {
        let saved = AnalysisSettings.liveHintsEnabled
        defer { AnalysisSettings.liveHintsEnabled = saved }

        AnalysisSettings.liveHintsEnabled = true
        let model = RecordingSessionViewModel()
        model.startRecording()

        // Give the analysis task time to initiate/run
        for _ in 0..<60 {
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

    @Test @MainActor
    func undoLastPreservesExistingRecordWhenMovesRemain() throws {
        let model = RecordingSessionViewModel()
        model.startRecording()

        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)
        let e5 = try #require(Move(san: "e5", position: model.engine.board.position))
        try model.commit(move: e5)

        let record1 = try #require(model.savedRecordIfNeeded())
        #expect(record1.pgn.contains("e4"))
        #expect(record1.pgn.contains("e5"))

        model.undoLast()

        #expect(model.savedRecord != nil)
        let record2 = try #require(model.savedRecordIfNeeded())
        #expect(record2 === record1)
        #expect(record2.pgn.contains("e4"))
        #expect(!record2.pgn.contains("e5"))

        let c5 = try #require(Move(san: "c5", position: model.engine.board.position))
        try model.commit(move: c5)

        let record3 = try #require(model.savedRecordIfNeeded())
        #expect(record3 === record1)
        #expect(record3.pgn.contains("c5"))
    }

    @Test @MainActor
    func undoLastClearsCachedAnalysisOnSavedRecord() throws {
        let model = RecordingSessionViewModel()
        model.startRecording()

        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)
        let e5 = try #require(Move(san: "e5", position: model.engine.board.position))
        try model.commit(move: e5)

        let record = try #require(model.savedRecordIfNeeded())
        let persisted = PersistedGameAnalysis(
            schemaVersion: 1,
            speedRaw: "fast",
            analyzedAt: .now,
            result: .empty
        )
        record.savePersistedAnalysis(persisted)
        #expect(record.hasCachedAnalysis)

        model.undoLast()

        #expect(!record.hasCachedAnalysis)
        #expect(model.savedRecord === record)
    }

    @Test
    func formatLiveDebugLineNormalRecordingPhase() {
        let clock = ContinuousClock()
        let now = clock.now
        let occ = Occupancy.standardStart()

        let line = RecordingSessionViewModel.formatLiveDebugLine(
            phase: .recording,
            motion: .stable(occ),
            hamming: 0,
            changedSquareCount: 0,
            decision: .wait,
            inference: .none,
            lastCommittedOccupancy: occ,
            smoothedOccupancy: occ,
            lastIgnoredAt: nil,
            now: now
        )
        #expect(line == "rec  stable  ham 0  Δ0")
        #expect(!line.contains("ply"))
        #expect(!line.contains("-"))
    }

    @Test
    func formatLiveDebugLineDisturbedMotion() {
        let clock = ContinuousClock()
        let now = clock.now
        let occ = Occupancy.standardStart()

        let line = RecordingSessionViewModel.formatLiveDebugLine(
            phase: .recording,
            motion: .disturbed(since: occ),
            hamming: 2,
            changedSquareCount: 2,
            decision: .wait,
            inference: .none,
            lastCommittedOccupancy: occ,
            smoothedOccupancy: occ,
            lastIgnoredAt: nil,
            now: now
        )
        #expect(line == "rec  disturbed  ham 2  Δ2")
    }

    @Test
    func formatLiveDebugLineIgnoredIllegalDeltaWithCountdown() {
        let clock = ContinuousClock()
        let ignoredTime = clock.now
        let now = ignoredTime + .milliseconds(600) // 0.6s elapsed, 1.4s remaining of 2.0s TTL
        let start = Occupancy.standardStart()
        var smoothed = start
        smoothed.set(ChessSquare.parse("e4")!, occupied: true)
        smoothed.set(ChessSquare.parse("d5")!, occupied: true)

        let line = RecordingSessionViewModel.formatLiveDebugLine(
            phase: .recording,
            motion: .stable(smoothed),
            hamming: 2,
            changedSquareCount: 2,
            decision: .skipIgnored,
            inference: .none,
            lastCommittedOccupancy: start,
            smoothedOccupancy: smoothed,
            lastIgnoredAt: ignoredTime,
            now: now
        )
        #expect(line == "rec  stable  ham 2  Δ2  ignored: illegal delta [e4, d5] (1.4s)")
    }

    @Test
    func formatLiveDebugLineIgnoredIllegalDeltaDirectInference() {
        let clock = ContinuousClock()
        let now = clock.now
        let start = Occupancy.standardStart()
        var smoothed = start
        smoothed.set(ChessSquare.parse("e4")!, occupied: true)
        smoothed.set(ChessSquare.parse("d5")!, occupied: true)

        let line = RecordingSessionViewModel.formatLiveDebugLine(
            phase: .recording,
            motion: .stable(smoothed),
            hamming: 2,
            changedSquareCount: 2,
            decision: .infer(smoothed),
            inference: .illegal,
            lastCommittedOccupancy: start,
            smoothedOccupancy: smoothed,
            lastIgnoredAt: now,
            now: now
        )
        #expect(line == "rec  stable  ham 2  Δ2  ignored: illegal delta [e4, d5] (2.0s)")
    }

    @Test
    func formatLiveDebugLineTruncatesMoreThanFourChangedSquares() {
        let clock = ContinuousClock()
        let now = clock.now
        let start = Occupancy.standardStart()
        var smoothed = start
        // Change 5 squares: a3, b3, c3, d3, e3
        for sqName in ["a3", "b3", "c3", "d3", "e3"] {
            smoothed.set(ChessSquare.parse(sqName)!, occupied: true)
        }

        let line = RecordingSessionViewModel.formatLiveDebugLine(
            phase: .recording,
            motion: .stable(smoothed),
            hamming: 5,
            changedSquareCount: 5,
            decision: .skipIgnored,
            inference: .none,
            lastCommittedOccupancy: start,
            smoothedOccupancy: smoothed,
            lastIgnoredAt: now,
            now: now
        )
        #expect(line == "rec  stable  ham 5  Δ5  ignored: illegal delta [a3, b3, c3, d3...] (2.0s)")
    }

    @Test @MainActor
    func formatLiveDebugLineAwaitingEditCandidateMoves() throws {
        let clock = ContinuousClock()
        let now = clock.now
        let model = RecordingSessionViewModel()
        let move1 = try #require(Move(san: "Nf3", position: model.engine.board.position))
        let move2 = try #require(Move(san: "Nc3", position: model.engine.board.position))
        let occ = Occupancy.standardStart()

        let line = RecordingSessionViewModel.formatLiveDebugLine(
            phase: .awaitingEdit,
            motion: .stable(occ),
            hamming: 2,
            changedSquareCount: 0,
            decision: .wait,
            inference: .none,
            lastCommittedOccupancy: occ,
            smoothedOccupancy: occ,
            lastIgnoredAt: nil,
            now: now,
            ambiguousMoves: [move1, move2]
        )
        #expect(line == "edit  stable  ham 2  Δ0  amb Nf3,Nc3")
    }
}
