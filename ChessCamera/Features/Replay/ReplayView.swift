import SwiftUI
import UIKit

struct ReplayView: View {
    let pgn: String
    let title: String
    var initialFen: String? = nil

    @State private var plyIndex = 0
    @State private var sans: [String] = []
    @State private var fens: [String] = []
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var analysisResult: GameAnalysisResult?
    @State private var analysisProgress: GameAnalyzer.Progress?
    @State private var analysisMessage: String?
    @State private var isAnalyzing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AnalysisSettings.postGameKey) private var postGameEnabled = true
    @AppStorage(AnalysisSettings.postShowEvalBarKey) private var showEvalBar = true
    @AppStorage(AnalysisSettings.postShowArrowKey) private var showArrow = true
    @AppStorage(AnalysisSettings.postShowPVKey) private var showPV = true
    @AppStorage(AnalysisSettings.postShowLabelsKey) private var showLabels = true
    @AppStorage(AnalysisSettings.postShowAccuracyKey) private var showAccuracy = true
    @AppStorage(AnalysisSettings.postShowGraphKey) private var showGraph = true

    private let analysisEngine: any ChessAnalyzing = AnalysisServiceFactory.make()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    boardRow
                    if AnalysisSettings.effectivePostShowAccuracy, let result = analysisResult {
                        accuracyRow(result)
                    }
                    if AnalysisSettings.effectivePostShowPV, let pv = currentPVCaption {
                        Text(pv)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    if isAnalyzing, let progress = analysisProgress {
                        Text("Analyzing \(progress.completed)/\(progress.total)…")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    } else if let analysisMessage {
                        Text(analysisMessage)
                            .font(.callout)
                            .foregroundStyle(Theme.caution)
                            .padding(.horizontal, 16)
                    }
                    if AnalysisSettings.effectivePostShowGraph, let result = analysisResult, result.evalSeries.count > 1 {
                        EvalGraphView(series: result.evalSeries, selectedIndex: plyIndex) { index in
                            plyIndex = index
                        }
                        .padding(.horizontal, 16)
                    }
                    plyControls
                    MoveListView(
                        sans: sans,
                        selectedPly: plyIndex == 0 ? nil : plyIndex - 1,
                        qualities: qualityMap,
                        showsQualityLabels: AnalysisSettings.effectivePostShowLabels
                    ) { index in
                        plyIndex = index + 1
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 160)
                }
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share PGN") { sharePGN() }
                    Button("Copy PGN") { UIPasteboard.general.string = pgn }
                    Button("Copy FEN") { UIPasteboard.general.string = finalFEN }
                    Button("Copy current position FEN") { UIPasteboard.general.string = currentFEN }
                    if postGameEnabled {
                        Button(isAnalyzing ? "Analyzing…" : "Re-analyze") {
                            Task { await runAnalysis() }
                        }
                        .disabled(isAnalyzing || sans.isEmpty)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share")
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .onAppear { rebuild() }
        .task(id: postGameEnabled) {
            if postGameEnabled {
                await runAnalysis()
            } else {
                analysisResult = nil
                analysisMessage = nil
                await analysisEngine.stop()
            }
        }
        .onDisappear {
            Task { await analysisEngine.stop() }
        }
    }

    @ViewBuilder
    private var boardRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if AnalysisSettings.effectivePostShowEvalBar {
                EvalBarView(score: currentEval, height: 220)
            }
            DigitalBoardView(
                fen: currentFEN,
                lastMove: lastMoveHighlight,
                bestMove: currentBestArrow
            )
        }
        .padding(.horizontal, 16)
    }

    private var plyControls: some View {
        HStack(spacing: 16) {
            Button {
                plyIndex = max(plyIndex - 1, 0)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(plyIndex == 0)
            .accessibilityLabel("Previous move")

            Text(plyCaption)
                .font(.body.monospaced())
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)

            Button {
                plyIndex = min(plyIndex + 1, sans.count)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(plyIndex >= sans.count)
            .accessibilityLabel("Next move")
        }
        .padding(.horizontal, 16)
    }

    private func accuracyRow(_ result: GameAnalysisResult) -> some View {
        HStack(spacing: 16) {
            accuracyChip(title: "White", value: result.whiteAccuracy)
            accuracyChip(title: "Black", value: result.blackAccuracy)
        }
        .padding(.horizontal, 16)
    }

    private func accuracyChip(title: String, value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value.map { String(format: "%.0f%%" , $0) } ?? "—")
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(value.map { "\(title) accuracy \($0, specifier: "%.0f") percent" } ?? "\(title) accuracy unavailable")
    }

    private var currentFEN: String {
        guard plyIndex >= 0, plyIndex < fens.count else {
            return initialFen ?? FenCodec.standard
        }
        return fens[plyIndex]
    }

    private var finalFEN: String {
        fens.last ?? initialFen ?? FenCodec.standard
    }

    private var lastMoveHighlight: (from: ChessSquare, to: ChessSquare)? {
        guard plyIndex > 0, plyIndex <= sans.count else { return nil }
        do {
            let engine = GameEngine()
            for san in sans.prefix(plyIndex) {
                try engine.apply(san: san)
            }
            return engine.lastMoveSquares
        } catch {
            return nil
        }
    }

    private var currentEval: EvaluationScore? {
        guard let result = analysisResult else { return nil }
        if plyIndex < result.evalSeries.count {
            return result.evalSeries[plyIndex]
        }
        return result.plies.last?.playedScore
    }

    private var currentBestArrow: BoardArrow? {
        guard AnalysisSettings.effectivePostShowArrow else { return nil }
        guard plyIndex < sans.count, let result = analysisResult else { return nil }
        return result.plies.first(where: { $0.plyIndex == plyIndex })?.best.bestArrow
    }

    private var currentPVCaption: String? {
        guard plyIndex < sans.count, let result = analysisResult,
              let ply = result.plies.first(where: { $0.plyIndex == plyIndex }) else { return nil }
        let uci = ply.best.pvUCI.prefix(6).joined(separator: " ")
        guard !uci.isEmpty else { return nil }
        return "PV \(uci)"
    }

    private var qualityMap: [Int: MoveQuality] {
        guard let result = analysisResult else { return [:] }
        var map: [Int: MoveQuality] = [:]
        for ply in result.plies {
            if let quality = ply.quality {
                map[ply.plyIndex] = quality
            }
        }
        return map
    }

    private var plyCaption: String {
        if plyIndex == 0 { return "Start" }
        var text = "\(plyIndex)/\(sans.count)  \(sans[plyIndex - 1])"
        if AnalysisSettings.effectivePostShowLabels,
           let quality = qualityMap[plyIndex - 1],
           !quality.glyph.isEmpty {
            text += " \(quality.glyph)"
        }
        return text
    }

    private func rebuild() {
        sans = PGNMoveList.sans(from: pgn)
        var frames = [initialFen ?? FenCodec.standard]
        let engine: GameEngine
        if let initialFen, let loaded = try? GameEngine(fen: initialFen) {
            engine = loaded
        } else {
            engine = GameEngine()
        }
        for san in sans {
            do {
                try engine.apply(san: san)
                frames.append(engine.fen)
            } catch {
                break
            }
        }
        fens = frames
        plyIndex = 0
    }

    private func runAnalysis() async {
        guard AnalysisSettings.postGameEnabled, !sans.isEmpty, fens.count == sans.count + 1 else { return }
        isAnalyzing = true
        analysisMessage = nil
        analysisProgress = GameAnalyzer.Progress(completed: 0, total: sans.count)
        let analyzer = GameAnalyzer(engine: analysisEngine)
        let sansCopy = sans
        let fensCopy = fens
        let result = await analyzer.analyze(sans: sansCopy, fens: fensCopy) { progress in
            Task { @MainActor in
                analysisProgress = progress
            }
        }
        let availability = await analysisEngine.availability
        await MainActor.run {
            isAnalyzing = false
            analysisProgress = nil
            if result.plies.isEmpty, let message = availability.userMessage {
                analysisMessage = message
                analysisResult = nil
            } else {
                analysisResult = result
                analysisMessage = nil
            }
        }
    }

    private func sharePGN() {
        do {
            shareItems = [try PGNShareFile.write(pgn: pgn, title: title)]
            showShare = true
        } catch {
            UIPasteboard.general.string = pgn
        }
    }
}

#Preview {
    NavigationStack {
        ReplayView(pgn: "1. e4 e5 2. Nf3", title: "Game · Sep 9")
    }
}
