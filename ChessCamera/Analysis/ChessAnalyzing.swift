import Foundation

/// Seam for Stockfish (or a fake in tests). Never call ChessKitEngine from UI directly.
protocol ChessAnalyzing: Sendable {
    var availability: AnalysisAvailability { get async }
    func start(threads: Int, hashMB: Int) async
    func stop() async
    /// Analyze `request.fen`. Cancels any in-flight search first.
    func analyze(_ request: AnalysisRequest) async -> PositionAnalysis?
}

/// Shared factory used by live recording and replay.
enum AnalysisServiceFactory {
    static let shared: any ChessAnalyzing = AnalysisService()

    static func make() -> any ChessAnalyzing {
        shared
    }
}
