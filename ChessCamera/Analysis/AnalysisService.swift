import ChessKitEngine
import Foundation

/// On-device Stockfish 17 via ChessKitEngine. One instance at a time.
actor AnalysisService: ChessAnalyzing {
    private var engine: Engine?
    private var listenTask: Task<Void, Never>?
    private var latestInfo: EngineResponse.Info?
    private var latestBestMove: String?
    private var searchContinuation: CheckedContinuation<PositionAnalysis?, Never>?
    private var searchID: UInt64 = 0
    private var activeSearchID: UInt64 = 0
    private var currentFEN: String?
    private var started = false
    private var availabilityState: AnalysisAvailability = .ready

    var availability: AnalysisAvailability { availabilityState }

    static var nnuePresent: Bool {
        Bundle.main.url(forResource: "nn-37f18f62d772", withExtension: "nnue") != nil
            || Bundle.main.url(forResource: "nn-1111cefa1111", withExtension: "nnue") != nil
    }

    func start(threads: Int, hashMB: Int) async {
        if started { return }
        guard Self.nnuePresent else {
            availabilityState = .missingNNUE
            return
        }

        let engine = Engine(type: .stockfish)
        self.engine = engine
        // ChessKitEngine sets Threads to max(coreCount - 1, 1). Pass threads + 1.
        await engine.start(coreCount: max(threads + 1, 2), multipv: 1)

        // Wait until UCI handshake completes (readyok → isRunning).
        for _ in 0..<100 {
            if await engine.isRunning { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard await engine.isRunning else {
            availabilityState = .failed("Stockfish failed to start.")
            await engine.stop()
            self.engine = nil
            return
        }

        await engine.send(command: .setoption(id: "Hash", value: "\(hashMB)"))
        if let small = Bundle.main.url(forResource: "nn-37f18f62d772", withExtension: "nnue")?.path() {
            await engine.send(command: .setoption(id: "EvalFile", value: small))
            await engine.send(command: .setoption(id: "EvalFileSmall", value: small))
        }
        started = true
        availabilityState = .ready
        beginListening()
    }

    func stop() async {
        searchID &+= 1
        activeSearchID = searchID
        if let cont = searchContinuation {
            searchContinuation = nil
            cont.resume(returning: nil)
        }
        listenTask?.cancel()
        listenTask = nil
        latestInfo = nil
        latestBestMove = nil
        currentFEN = nil
        if let engine {
            await engine.stop()
        }
        engine = nil
        started = false
    }

    func analyze(_ request: AnalysisRequest) async -> PositionAnalysis? {
        if !started {
            await start(threads: request.threads, hashMB: request.hashMB)
        }
        guard started, let engine else {
            return nil
        }

        // Cancel any in-flight search.
        searchID &+= 1
        let thisSearch = searchID
        activeSearchID = thisSearch
        if searchContinuation != nil {
            await engine.send(command: .stop)
            if let cont = searchContinuation {
                searchContinuation = nil
                cont.resume(returning: nil)
            }
        }

        latestInfo = nil
        latestBestMove = nil
        currentFEN = request.fen

        await engine.send(command: .setoption(id: "Hash", value: "\(request.hashMB)"))
        await engine.send(command: .stop)
        await engine.send(command: .position(.fen(request.fen)))
        await engine.send(command: .go(movetime: request.movetimeMs))

        return await withCheckedContinuation { (cont: CheckedContinuation<PositionAnalysis?, Never>) in
            // Only attach if this search is still the active one.
            if activeSearchID == thisSearch {
                searchContinuation = cont
            } else {
                cont.resume(returning: nil)
            }
        }
    }

    // MARK: - Private

    private func beginListening() {
        listenTask?.cancel()
        guard let engine else { return }
        listenTask = Task { [weak self] in
            guard let stream = await engine.responseStream else { return }
            for await response in stream {
                guard let self else { break }
                await self.handle(response)
            }
        }
    }

    private func handle(_ response: EngineResponse) {
        switch response {
        case let .info(info):
            if info.score != nil {
                latestInfo = info
            } else if latestInfo == nil {
                latestInfo = info
            } else if let depth = info.depth, let prev = latestInfo?.depth, depth >= prev {
                var merged = latestInfo!
                if let pv = info.pv { merged.pv = pv }
                if let score = info.score { merged.score = score }
                merged.depth = depth
                latestInfo = merged
            }
        case let .bestmove(move, _):
            latestBestMove = move
            finishSearch(bestMove: move)
        default:
            break
        }
    }

    private func finishSearch(bestMove: String) {
        guard let cont = searchContinuation else { return }
        searchContinuation = nil
        let fen = currentFEN ?? FenCodec.standard
        let analysis = makeAnalysis(fen: fen, bestMove: bestMove, info: latestInfo)
        cont.resume(returning: analysis)
    }

    private func makeAnalysis(
        fen: String,
        bestMove: String,
        info: EngineResponse.Info?
    ) -> PositionAnalysis {
        let sideWhite = FenSide.toMove(fen) == "w"
        let scoreSTM = score(from: info?.score) ?? .centipawns(0)
        let whiteScore = scoreSTM.whitePOV(sideToMoveIsWhite: sideWhite)
        let pv = info?.pv ?? (bestMove == "(none)" ? [] : [bestMove])
        let uci = bestMove == "(none)" ? nil : bestMove
        return PositionAnalysis(
            fen: fen,
            score: whiteScore,
            bestMoveUCI: uci,
            bestArrow: uci.flatMap(UCIMove.arrow(from:)),
            pvUCI: pv,
            depth: info?.depth
        )
    }

    private func score(from score: EngineResponse.Info.Score?) -> EvaluationScore? {
        guard let score else { return nil }
        if let mate = score.mate {
            return .mate(mate)
        }
        if let cp = score.cp {
            return .centipawns(Int(cp.rounded()))
        }
        return nil
    }
}
