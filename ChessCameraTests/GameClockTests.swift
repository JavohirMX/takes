import ChessKit
import Foundation
import Testing
@testable import Takes

@Suite("Game clocks")
struct GameClockControllerTests {
    @Test
    func incrementAppliesAfterCommit() {
        let clocks = GameClockController()
        clocks.configure(base: 300, increment: 5)
        clocks.startIfNeeded(side: .white)

        #expect(clocks.whiteRemaining == 300)
        #expect(clocks.blackRemaining == 300)

        _ = clocks.tick(delta: 10)
        #expect(clocks.whiteRemaining == 290)

        clocks.onMoveCommitted(newSide: .black)
        #expect(clocks.whiteRemaining == 295)
        #expect(clocks.blackRemaining == 300)
        #expect(clocks.activeSide == .black)
        #expect(clocks.isRunning)
    }

    @Test
    func pauseStopsTicking() {
        let clocks = GameClockController()
        clocks.configure(base: 60, increment: 0)
        clocks.startIfNeeded(side: .white)
        _ = clocks.tick(delta: 5)
        #expect(clocks.whiteRemaining == 55)

        clocks.pause()
        #expect(clocks.tick(delta: 10) == nil)
        #expect(clocks.whiteRemaining == 55)
        #expect(!clocks.isRunning)
    }

    @Test
    func tickReturnsFlaggedSideAtZero() {
        let clocks = GameClockController()
        clocks.configure(base: 3, increment: 0)
        clocks.startIfNeeded(side: .black)

        #expect(clocks.tick(delta: 2) == nil)
        #expect(clocks.blackRemaining == 1)

        let flagged = clocks.tick(delta: 2)
        #expect(flagged == .black)
        #expect(clocks.blackRemaining == 0)
        #expect(!clocks.isRunning)
    }

    @Test
    func offPresetNeverTicks() {
        let clocks = GameClockController()
        clocks.configureOff()
        clocks.startIfNeeded(side: .white)
        #expect(!clocks.isEnabled)
        #expect(clocks.tick(delta: 30) == nil)
        #expect(clocks.whiteRemaining == 0)

        clocks.configure(base: 0, increment: 3)
        #expect(!clocks.isEnabled)
        #expect(clocks.tick(delta: 1) == nil)
    }

    @Test
    func formatRemainingUsesMinutesAndSeconds() {
        #expect(GameClockController.format(remaining: 125) == "2:05")
        #expect(GameClockController.format(remaining: 59.9) == "0:59")
        #expect(GameClockController.format(remaining: 3661) == "1:01:01")
    }
}

@Suite("Game clock session integration")
struct GameClockSessionTests {
    @Test @MainActor
    func incrementAfterCommitViaSession() throws {
        let model = RecordingSessionViewModel()
        model.sessionClockPreset = .fivePlusThree
        model.proposedFEN = FenCodec.standard
        model.startRecording(mode: .newGame)
        model.stopClockTicker()

        #expect(model.clocks.isEnabled)
        #expect(model.clocks.whiteRemaining == 300)

        model.advanceClocks(delta: 7)
        #expect(model.clocks.whiteRemaining == 293)

        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)

        #expect(model.clocks.whiteRemaining == 296)
        #expect(model.clocks.activeSide == .black)
    }

    @Test @MainActor
    func pauseWhileDisturbed() {
        let model = RecordingSessionViewModel()
        model.sessionClockPreset = .tenPlusFive
        model.proposedFEN = FenCodec.standard
        model.startRecording(mode: .newGame)
        model.stopClockTicker()

        model.advanceClocks(delta: 4)
        let afterTick = model.clocks.whiteRemaining
        #expect(afterTick == 596)

        model.phase = .disturbed
        model.advanceClocks(delta: 20)
        #expect(model.clocks.whiteRemaining == afterTick)
        #expect(!model.clocks.isRunning)
    }

    @Test @MainActor
    func flagFinishesWithTerminalResult() {
        let model = RecordingSessionViewModel()
        model.sessionClockPreset = .custom
        model.proposedFEN = FenCodec.standard
        model.startRecording(mode: .newGame)
        model.stopClockTicker()
        model.clocks.configure(base: 2, increment: 0)
        model.clocks.startIfNeeded(side: .white)

        model.advanceClocks(delta: 1)
        #expect(model.phase == .recording)

        model.advanceClocks(delta: 2)
        #expect(model.phase == .gameOver)
        #expect(model.pendingResultOverride == "0-1")
    }

    @Test @MainActor
    func offPresetNeverTicksInSession() {
        let model = RecordingSessionViewModel()
        model.sessionClockPreset = .off
        model.proposedFEN = FenCodec.standard
        model.startRecording(mode: .newGame)
        model.stopClockTicker()

        #expect(!model.clocks.isEnabled)
        model.advanceClocks(delta: 50)
        #expect(model.clocks.whiteRemaining == 0)
        #expect(model.phase == .recording)
    }

    @Test
    func gameRecordIncludesTimeControlHeader() {
        let record = GameRecord(
            createdAt: .now,
            pgn: "1. e4 e5 *",
            finalFen: FenCodec.standard,
            title: "Timed",
            timeControl: "600+5",
            whiteTimeRemaining: 580,
            blackTimeRemaining: 600
        )
        #expect(record.pgnWithHeaders.contains("[TimeControl \"600+5\"]"))
        #expect(record.whiteTimeRemaining == 580)
        #expect(record.blackTimeRemaining == 600)
    }

    @Test
    func gameClockSettingsTimeControlStrings() {
        #expect(GameClockSettings.timeControlString(for: .off) == nil)
        #expect(GameClockSettings.timeControlString(for: .fivePlusThree) == "300+3")
        #expect(GameClockSettings.timeControlString(for: .tenPlusFive) == "600+5")
        #expect(GameClockSettings.timeControlString(for: .fifteenPlusTen) == "900+10")
    }
}

@Suite("Move think timer")
struct MoveThinkTimerTests {
    @Test
    func accumulatesWhileRunningAndFreezesAcrossPause() {
        let timer = MoveThinkTimer()
        timer.startThink(for: .white)
        timer.tick(delta: 1.5)
        #expect(abs(timer.currentThinkElapsed - 1.5) < 0.001)

        timer.pauseThink()
        timer.tick(delta: 10)
        #expect(abs(timer.currentThinkElapsed - 1.5) < 0.001)

        timer.resumeThinkIfNeeded()
        timer.tick(delta: 0.5)
        #expect(abs(timer.currentThinkElapsed - 2.0) < 0.001)

        let consumed = timer.consumeThinkTime()
        #expect(abs(consumed - 2.0) < 0.001)
        #expect(timer.currentThinkElapsed == 0)
        #expect(!timer.isRunning)
    }

    @Test
    func formatCompactAndEMT() {
        #expect(MoveThinkTimer.formatCompact(12.4) == "12.4s")
        #expect(MoveThinkTimer.formatCompact(12.0) == "12s")
        #expect(MoveThinkTimer.formatCompact(65) == "1:05")
        #expect(MoveThinkTimer.formatEMT(83) == "0:01:23")
        #expect(MoveThinkTimer.formatEMT(3661) == "1:01:01")
    }

    @Test
    func annotatedPGNRoundTripPreservesSansAndTimes() {
        let sans = ["e4", "e5", "Nf3"]
        let times: [TimeInterval] = [5, 12, 83]
        let annotated = PGNMoveList.annotatedMovetext(sans: sans, moveTimes: times, result: "*")
        #expect(annotated.contains("[%emt 0:00:05]"))
        #expect(annotated.contains("[%emt 0:00:12]"))
        #expect(annotated.contains("[%emt 0:01:23]"))
        #expect(PGNMoveList.sans(from: annotated) == sans)
        #expect(PGNMoveList.emtSeconds(from: annotated) == times)
    }

    @Test @MainActor
    func commitAppendsThinkTimeWithClocksOff() throws {
        let model = RecordingSessionViewModel()
        model.sessionClockPreset = .off
        model.proposedFEN = FenCodec.standard
        model.startRecording(mode: .newGame)
        model.stopClockTicker()

        #expect(!model.clocks.isEnabled)
        model.advanceClocks(delta: 3.2)
        #expect(abs(model.thinkTimer.currentThinkElapsed - 3.2) < 0.001)

        let e4 = try #require(Move(san: "e4", position: model.engine.board.position))
        try model.commit(move: e4)

        #expect(model.committedMoveTimes.count == 1)
        #expect(abs(model.committedMoveTimes[0] - 3.2) < 0.001)
        #expect(model.thinkTimer.currentThinkElapsed == 0)
        #expect(model.thinkTimer.thinkingSide == .black)
    }

    @Test @MainActor
    func thinkPausesWhileDisturbed() {
        let model = RecordingSessionViewModel()
        model.sessionClockPreset = .off
        model.proposedFEN = FenCodec.standard
        model.startRecording(mode: .newGame)
        model.stopClockTicker()

        model.advanceClocks(delta: 2)
        model.phase = .disturbed
        model.advanceClocks(delta: 20)
        #expect(abs(model.thinkTimer.currentThinkElapsed - 2) < 0.001)
        #expect(!model.thinkTimer.isRunning)
    }

    @Test @MainActor
    func undoAndReplaceAtPlyTruncateMoveTimes() throws {
        let model = RecordingSessionViewModel()
        model.sessionClockPreset = .off
        model.proposedFEN = FenCodec.standard
        model.startRecording(mode: .newGame)
        model.stopClockTicker()

        model.advanceClocks(delta: 1)
        try model.commit(move: try #require(Move(san: "e4", position: model.engine.board.position)))
        model.advanceClocks(delta: 2)
        try model.commit(move: try #require(Move(san: "e5", position: model.engine.board.position)))
        model.advanceClocks(delta: 3)
        try model.commit(move: try #require(Move(san: "Nf3", position: model.engine.board.position)))
        #expect(model.committedMoveTimes.count == 3)

        model.undoLast()
        #expect(model.committedMoveTimes.count == 2)

        model.beginEdit(atPly: 0)
        model.applyEdit(san: "d4")
        #expect(model.committedSANs == ["d4"])
        #expect(model.committedMoveTimes == [0])
    }

    @Test
    func gameRecordPersistsMoveTimesAndAnnotatesPGN() {
        let record = GameRecord(
            createdAt: .now,
            pgn: "1. e4 e5 *",
            finalFen: FenCodec.standard,
            title: "Timed moves",
            moveTimes: [4, 9]
        )
        #expect(record.moveTimes == [4, 9])
        #expect(record.pgnWithHeaders.contains("[%emt 0:00:04]"))
        #expect(record.pgnWithHeaders.contains("[%emt 0:00:09]"))
        #expect(PGNMoveList.sans(from: record.pgnWithHeaders) == ["e4", "e5"])
    }
}
