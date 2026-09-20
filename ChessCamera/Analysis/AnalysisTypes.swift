import Foundation

/// Engine evaluation from White's point of view.
enum EvaluationScore: Equatable, Sendable, Hashable, Codable {
    case centipawns(Int)
    case mate(Int)

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum Kind: String, Codable {
        case centipawns
        case mate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        let value = try container.decode(Int.self, forKey: .value)
        switch kind {
        case .centipawns: self = .centipawns(value)
        case .mate: self = .mate(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .centipawns(let cp):
            try container.encode(Kind.centipawns, forKey: .type)
            try container.encode(cp, forKey: .value)
        case .mate(let moves):
            try container.encode(Kind.mate, forKey: .type)
            try container.encode(moves, forKey: .value)
        }
    }

    /// Display string, White-positive (e.g. `+0.42`, `-1.2`, `M3`, `-M2`).
    var display: String {
        switch self {
        case .centipawns(let cp):
            let pawns = Double(cp) / 100.0
            if abs(pawns) < 0.005 { return "0.00" }
            return String(format: "%+.2f", pawns)
        case .mate(let moves):
            if moves == 0 { return "M0" }
            return moves > 0 ? "M\(moves)" : "-M\(-moves)"
        }
    }

    /// Approximate centipawns for graphs / win% (mate ≈ ±10_000).
    var approximateCentipawns: Int {
        switch self {
        case .centipawns(let cp):
            return cp
        case .mate(let moves):
            if moves == 0 { return 10_000 }
            return moves > 0 ? 10_000 - abs(moves) * 10 : -10_000 + abs(moves) * 10
        }
    }

    /// Fraction of the eval bar filled by White (0…1). Mate saturates.
    var whiteBarFraction: Double {
        switch self {
        case .mate(let moves):
            return moves >= 0 ? 1 : 0
        case .centipawns(let cp):
            let pawns = Double(cp) / 100.0
            let clamped = max(-8, min(8, pawns))
            return (clamped + 8) / 16
        }
    }
}

import SwiftUI

enum MoveQuality: String, Sendable, Equatable, CaseIterable, Codable {
    case brilliant
    case great
    case best
    case excellent
    case good
    case book
    case inaccuracy
    case mistake
    case blunder
    case missedWin

    var title: String {
        switch self {
        case .brilliant: "Brilliant"
        case .great: "Great"
        case .best: "Best"
        case .excellent: "Excellent"
        case .good: "Good"
        case .book: "Book"
        case .inaccuracy: "Inaccuracy"
        case .mistake: "Mistake"
        case .blunder: "Blunder"
        case .missedWin: "Missed Win"
        }
    }

    var glyph: String {
        switch self {
        case .brilliant: "!!"
        case .great: "!"
        case .best: "★"
        case .excellent: "✓"
        case .good: ""
        case .book: "📖"
        case .inaccuracy: "?!"
        case .mistake: "?"
        case .blunder: "??"
        case .missedWin: "✕"
        }
    }

    var badgeColor: Color {
        switch self {
        case .brilliant: Color(red: 0.15, green: 0.75, blue: 0.75) // Cyan
        case .great: Color(red: 0.35, green: 0.65, blue: 0.95) // Light Blue
        case .best: Color(red: 0.28, green: 0.75, blue: 0.35) // Vibrant Green
        case .excellent: Color(red: 0.38, green: 0.72, blue: 0.42) // Medium Green
        case .good: Color.gray.opacity(0.8)
        case .book: Color(red: 0.82, green: 0.60, blue: 0.35) // Warm amber / brown
        case .inaccuracy: Color(red: 0.95, green: 0.75, blue: 0.20) // Yellow
        case .mistake: Color(red: 0.95, green: 0.55, blue: 0.15) // Orange
        case .blunder: Color(red: 0.92, green: 0.25, blue: 0.25) // Red
        case .missedWin: Color(red: 0.88, green: 0.20, blue: 0.35) // Crimson
        }
    }

    var badgeForeground: Color {
        switch self {
        case .good: .white
        default: .white
        }
    }
}

struct BoardArrow: Equatable, Sendable, Hashable, Codable {
    var from: ChessSquare
    var to: ChessSquare
    var isBestMove: Bool = true
}

/// One engine snapshot for a FEN.
struct PositionAnalysis: Equatable, Sendable, Codable {
    var fen: String
    var score: EvaluationScore
    /// Best move in UCI (`e2e4`, `e7e8q`).
    var bestMoveUCI: String?
    var bestArrow: BoardArrow?
    /// Principal variation as UCI tokens.
    var pvUCI: [String]
    var depth: Int?

    var evalDisplay: String { score.display }
}

/// Per-ply annotation produced while walking a PGN.
struct PlyAnalysis: Equatable, Sendable, Identifiable, Codable {
    var id: Int { plyIndex }
    /// 0-based ply index into the SAN list.
    var plyIndex: Int
    /// FEN before the played move.
    var fenBefore: String
    /// Engine eval of `fenBefore` (best line).
    var best: PositionAnalysis
    /// Eval after the played move, flipped to White's POV when needed for graphs.
    var playedScore: EvaluationScore?
    var quality: MoveQuality?
    var winPercentBefore: Double
    var winPercentAfter: Double
    var winPercentLoss: Double

    enum CodingKeys: String, CodingKey {
        case plyIndex, fenBefore, best, playedScore, quality
        case winPercentBefore, winPercentAfter, winPercentLoss
    }
}

struct GameAnalysisResult: Equatable, Sendable, Codable {
    var plies: [PlyAnalysis]
    var whiteAccuracy: Double?
    var blackAccuracy: Double?
    var whiteElo: Int?
    var blackElo: Int?
    /// Eval after each ply (index 0 = start), White POV, for the graph.
    var evalSeries: [EvaluationScore]

    static let empty = GameAnalysisResult(
        plies: [],
        whiteAccuracy: nil,
        blackAccuracy: nil,
        whiteElo: nil,
        blackElo: nil,
        evalSeries: [.centipawns(0)]
    )
}

/// Versioned blob stored on `GameRecord.analysisJSON`.
struct PersistedGameAnalysis: Equatable, Sendable, Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var speedRaw: String
    var analyzedAt: Date
    var result: GameAnalysisResult

    static func encode(_ value: PersistedGameAnalysis) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode(from data: Data) -> PersistedGameAnalysis? {
        guard let value = try? JSONDecoder().decode(PersistedGameAnalysis.self, from: data),
              value.schemaVersion == currentSchemaVersion else {
            return nil
        }
        return value
    }
}

enum AnalysisAvailability: Equatable, Sendable {
    case ready
    case missingNNUE
    case failed(String)

    var userMessage: String? {
        switch self {
        case .ready: nil
        case .missingNNUE:
            "Analysis unavailable — run scripts/fetch-nnue.sh and rebuild."
        case .failed(let message):
            message
        }
    }
}

struct AnalysisRequest: Equatable, Sendable {
    var fen: String
    var movetimeMs: Int
    var threads: Int
    var hashMB: Int

    static func live(fen: String) -> AnalysisRequest {
        AnalysisRequest(
            fen: fen,
            movetimeMs: AnalysisSettings.liveMovetimeMs,
            threads: 1,
            hashMB: 16
        )
    }

    static func replay(fen: String) -> AnalysisRequest {
        let speed = AnalysisSettings.speed
        return AnalysisRequest(
            fen: fen,
            movetimeMs: speed.movetimeMs,
            threads: speed.threads,
            hashMB: speed.hashMB
        )
    }
}
