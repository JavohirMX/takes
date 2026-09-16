import Foundation

/// Deterministic fake engine for unit tests — never boots Stockfish.
actor FakeChessAnalyzer: ChessAnalyzing {
    /// Map FEN → canned analysis. Missing keys return a flat 0.00 eval.
    var fixtures: [String: PositionAnalysis]
    private(set) var startCount = 0
    private(set) var analyzeCount = 0

    init(fixtures: [String: PositionAnalysis] = [:]) {
        self.fixtures = fixtures
    }

    var availability: AnalysisAvailability { .ready }

    func start(threads: Int, hashMB: Int) async {
        startCount += 1
    }

    func stop() async {}

    func analyze(_ request: AnalysisRequest) async -> PositionAnalysis? {
        analyzeCount += 1
        if let fixture = fixtures[request.fen] {
            return fixture
        }
        return PositionAnalysis(
            fen: request.fen,
            score: .centipawns(0),
            bestMoveUCI: "e2e4",
            bestArrow: UCIMove.arrow(from: "e2e4"),
            pvUCI: ["e2e4"],
            depth: 8
        )
    }
}
