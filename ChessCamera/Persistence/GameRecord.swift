import Foundation
import SwiftData

@Model
final class GameRecord {
    var createdAt: Date
    var pgn: String
    var finalFen: String
    var title: String

    init(createdAt: Date, pgn: String, finalFen: String, title: String) {
        self.createdAt = createdAt
        self.pgn = pgn
        self.finalFen = finalFen
        self.title = title
    }

    static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "Game · \(formatter.string(from: date))"
    }
}
