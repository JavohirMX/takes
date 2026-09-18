import Foundation
import SwiftData

@Model
final class GameRecord {
    var createdAt: Date
    var pgn: String
    var finalFen: String
    var title: String
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

    init(
        createdAt: Date,
        pgn: String,
        finalFen: String,
        title: String,
        whitePlayer: String? = nil,
        blackPlayer: String? = nil,
        event: String? = nil,
        resultOverride: String? = nil,
        openingName: String? = nil
    ) {
        self.createdAt = createdAt
        self.pgn = pgn
        self.finalFen = finalFen
        self.title = title
        self.whitePlayer = whitePlayer
        self.blackPlayer = blackPlayer
        self.event = event
        self.resultOverride = resultOverride
        self.openingName = openingName ?? OpeningDetector.detect(pgn: pgn)
        self.analysisJSON = nil
        self.analysisSpeedRaw = nil
        self.analyzedAt = nil
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
        return tags.joined(separator: "\n") + "\n\n" + pgn
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
