import Foundation

/// Engine evaluation from White's point of view.
enum EvaluationScore: Equatable, Sendable, Hashable {
    case centipawns(Int)
    case mate(Int)

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
            // Soft clamp around ±8 pawns.
            let pawns = Double(cp) / 100.0
            let clamped = max(-8, min(8, pawns))
            return (clamped + 8) / 16
        }
    }
}

enum MoveQuality: String, Sendable, Equatable, CaseIterable {
    case best
    case excellent
    case good
    case inaccuracy
    case mistake
    case blunder

    var title: String {
        switch self {
        case .best: "Best"
        case .excellent: "Excellent"
        case .good: "Good"
        case .inaccuracy: "Inaccuracy"
        case .mistake: "Mistake"
        case .blunder: "Blunder"
        }
    }

    var glyph: String {
        switch self {
        case .best: "!!"
        case .excellent: "!"
        case .good: ""
        case .inaccuracy: "?!"
        case .mistake: "?"
        case .blunder: "??"
        }
    }
}

struct BoardArrow: Equatable, Sendable, Hashable {
    var from: ChessSquare
    var to: ChessSquare
}

/// One engine snapshot for a FEN.
struct PositionAnalysis: Equatable, Sendable {
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
struct PlyAnalysis: Equatable, Sendable, Identifiable {
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
}

struct GameAnalysisResult: Equatable, Sendable {
    var plies: [PlyAnalysis]
    var whiteAccuracy: Double?
    var blackAccuracy: Double?
    /// Eval after each ply (index 0 = start), White POV, for the graph.
    var evalSeries: [EvaluationScore]
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
