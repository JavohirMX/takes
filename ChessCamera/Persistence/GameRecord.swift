import Foundation
import SwiftData

@Model
final class GameRecord {
    var createdAt: Date
    var pgn: String
    var finalFen: String
    var title: String
    /// Encoded `PersistedGameAnalysis` JSON. Nil when never analyzed.
    var analysisJSON: Data?
    /// `AnalysisSpeed.rawValue` used for the cached analysis.
    var analysisSpeedRaw: String?
    var analyzedAt: Date?

    init(createdAt: Date, pgn: String, finalFen: String, title: String) {
        self.createdAt = createdAt
        self.pgn = pgn
        self.finalFen = finalFen
        self.title = title
        self.analysisJSON = nil
        self.analysisSpeedRaw = nil
        self.analyzedAt = nil
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
