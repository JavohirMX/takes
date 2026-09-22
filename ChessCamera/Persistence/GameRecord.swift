import Foundation
import SwiftData

@Model
final class GameRecord {
    var createdAt: Date
    var pgn: String
    var finalFen: String
    var title: String
    var initialFen: String?
    var whitePlayer: String?
    var blackPlayer: String?
    var event: String?
    var resultOverride: String?
    var openingName: String?
    /// Encoded `PersistedGameAnalysis` JSON. Nil when never analyzed.
    var analysisJSON: Data?
    /// `AnalysisSpeed.rawValue` used for the cached analysis.
    var analysisSpeedRaw: String?
    var analyzedAt: Date?
    /// PGN TimeControl value, e.g. `"600+5"`. Nil when clocks were Off.
    var timeControl: String?
    /// Remaining white clock seconds when last saved (for Continue).
    var whiteTimeRemaining: Double?
    /// Remaining black clock seconds when last saved (for Continue).
    var blackTimeRemaining: Double?
    /// Encoded `[Double]` think times (seconds) parallel to plies in `pgn`.
    var moveTimesJSON: Data?

    init(
        createdAt: Date,
        pgn: String,
        finalFen: String,
        title: String,
        initialFen: String? = nil,
        whitePlayer: String? = nil,
        blackPlayer: String? = nil,
        event: String? = nil,
        resultOverride: String? = nil,
        openingName: String? = nil,
        timeControl: String? = nil,
        whiteTimeRemaining: Double? = nil,
        blackTimeRemaining: Double? = nil,
        moveTimes: [TimeInterval]? = nil
    ) {
        self.createdAt = createdAt
        self.pgn = pgn
        self.finalFen = finalFen
        self.title = title
        self.initialFen = initialFen
        self.whitePlayer = whitePlayer
        self.blackPlayer = blackPlayer
        self.event = event
        self.resultOverride = resultOverride
        self.openingName = openingName ?? OpeningDetector.detect(pgn: pgn)
        self.analysisJSON = nil
        self.analysisSpeedRaw = nil
        self.analyzedAt = nil
        self.timeControl = timeControl
        self.whiteTimeRemaining = whiteTimeRemaining
        self.blackTimeRemaining = blackTimeRemaining
        self.moveTimesJSON = Self.encodeMoveTimes(moveTimes)
    }

    var moveTimes: [TimeInterval] {
        get { Self.decodeMoveTimes(moveTimesJSON) ?? [] }
        set { moveTimesJSON = Self.encodeMoveTimes(newValue.isEmpty ? nil : newValue) }
    }

    static func encodeMoveTimes(_ times: [TimeInterval]?) -> Data? {
        guard let times, !times.isEmpty else { return nil }
        return try? JSONEncoder().encode(times)
    }

    static func decodeMoveTimes(_ data: Data?) -> [TimeInterval]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([Double].self, from: data)
    }

    var displayResult: String {
        if let resultOverride, !resultOverride.isEmpty { return resultOverride }
        return (try? GameEngine(fen: finalFen))?.resultToken ?? "*"
    }

    var effectiveOpening: String? {
        if let openingName, !openingName.isEmpty { return openingName }
        return OpeningDetector.detect(pgn: pgn)
    }

    var pgnWithHeaders: String {
        var tags: [String] = []
        tags.append("[Event \"\(event ?? "Casual Game")\"]")
        let dateStr = createdAt.formatted(Date.ISO8601FormatStyle().year().month().day())
        tags.append("[Date \"\(dateStr)\"]")
        tags.append("[White \"\(whitePlayer ?? "White")\"]")
        tags.append("[Black \"\(blackPlayer ?? "Black")\"]")
        tags.append("[Result \"\(displayResult)\"]")
        if let opening = effectiveOpening {
            tags.append("[Opening \"\(opening)\"]")
        }
        if let timeControl, !timeControl.isEmpty {
            tags.append("[TimeControl \"\(timeControl)\"]")
        }
        if let initialFen, !FenCodec.isStandardStart(initialFen) {
            tags.append("[SetUp \"1\"]")
            tags.append("[FEN \"\(initialFen)\"]")
        }
        let body: String
        let times = moveTimes
        if times.isEmpty {
            body = pgn
        } else {
            let sans = PGNMoveList.sans(from: pgn)
            body = PGNMoveList.annotatedMovetext(
                sans: sans,
                moveTimes: times,
                result: displayResult
            )
        }
        return tags.joined(separator: "\n") + "\n\n" + body
    }

    var hasCachedAnalysis: Bool {
        analysisJSON != nil && loadPersistedAnalysis() != nil
    }

    func loadPersistedAnalysis() -> PersistedGameAnalysis? {
        guard let analysisJSON else { return nil }
        return PersistedGameAnalysis.decode(from: analysisJSON)
    }

    func savePersistedAnalysis(_ persisted: PersistedGameAnalysis) {
        analysisJSON = PersistedGameAnalysis.encode(persisted)
        analysisSpeedRaw = persisted.speedRaw
        analyzedAt = persisted.analyzedAt
    }

    func clearPersistedAnalysis() {
        analysisJSON = nil
        analysisSpeedRaw = nil
        analyzedAt = nil
    }

    static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "Game · \(formatter.string(from: date))"
    }
}
