import ChessKit
import SwiftData
import SwiftUI
import UIKit

struct ReplayView: View {
    let pgn: String
    let title: String
    var initialFen: String? = nil
    /// When set, load/save analysis cache on this SwiftData game.
    var gamePersistentID: PersistentIdentifier? = nil
    var engine: (any ChessAnalyzing)? = nil
    var onContinueGame: ((GameRecord) -> Void)? = nil
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var plyIndex = 0
    @State private var sans: [String] = []
    @State private var moveTimes: [TimeInterval] = []
    @State private var fens: [String] = []
    @State private var isFlipped = false
    @State private var isPlaying = false
    @State private var playbackTimer: Task<Void, Never>?
    @State private var showEditSheet = false
    @State private var showRecapSheet = false
    /// Mutable PGN so promote-to-mainline can rebuild without relying on the immutable `pgn` prop.
    @State private var activePGN = ""
    @State private var showPromoteConfirm = false
    @State private var currentInitialFen: String? = nil
    @State private var isMissingInitialPosition = false
    @State private var toastMessage: String?

    // Analysis state
    @State private var analysisResult: GameAnalysisResult?
    @State private var analysisProgress: GameAnalyzer.Progress?
    @State private var analysisMessage: String?
    @State private var isAnalyzing = false
    @State private var cachedSpeedRaw: String?
    @State private var analysisTask: Task<Void, Never>?

    // Interactive piece moves & in-memory variation exploration
    @State private var selectedSquare: ChessSquare?
    @State private var legalDestinations: [ChessSquare] = []
    @State private var variationEngine: GameEngine?
    @State private var variationBasePly: Int?
    @State private var variationSANs: [String] = []
    @State private var variationEval: EvaluationScore?
    @State private var variationBestArrow: BoardArrow?
    @State private var variationPVCaption: String?
    @State private var variationTask: Task<Void, Never>?

    @AppStorage(AnalysisSettings.postGameKey) private var postGameEnabled = true
    @AppStorage(AnalysisSettings.postShowEvalBarKey) private var showEvalBar = true
    @AppStorage(AnalysisSettings.postShowArrowKey) private var showArrow = true
    @AppStorage(AnalysisSettings.postShowPVKey) private var showPV = true
    @AppStorage(AnalysisSettings.postShowLabelsKey) private var showLabels = true
    @AppStorage(AnalysisSettings.postShowAccuracyKey) private var showAccuracy = true
    @AppStorage(AnalysisSettings.postShowGraphKey) private var showGraph = true

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var analysisEngine: any ChessAnalyzing { engine ?? AnalysisServiceFactory.shared }

    private var hasCachedResult: Bool {
        guard let result = analysisResult else { return false }
        return !result.plies.isEmpty && result.whiteAccuracy != nil
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            showRecapSheet = true
                        } label: {
                            Label("Share Recap Card", systemImage: "photo")
                        }
                        ShareLink(
                            item: pgnShareURL,
                            preview: SharePreview(title, image: Image(systemName: "square.and.arrow.up"))
                        ) {
                            Label("Share PGN", systemImage: "square.and.arrow.up")
                        }
                        ExternalAnalysisMenu(pgn: exportPGNString, onCopied: { msg in
                            toastMessage = msg
                        })
                        Button {
                            UIPasteboard.general.string = currentDisplayFEN
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            toastMessage = "FEN copied to clipboard"
                        } label: {
                            Label("Copy FEN", systemImage: "doc.on.doc")
                        }
                        if let record = resolveGameRecord() {
                            Button {
                                showEditSheet = true
                            } label: {
                                Label("Edit Game Details", systemImage: "pencil")
                            }
                            if record.displayResult == "*" || record.displayResult.isEmpty {
                                Button {
                                    onContinueGame?(record)
                                } label: {
                                    Label("Continue Recording Game", systemImage: "camera.viewfinder")
                                }
                            }
                        }
                        if postGameEnabled, hasCachedResult, !isAnalyzing, !sans.isEmpty {
                            Button {
                                startAnalysis()
                            } label: {
                                Label("Re-analyze", systemImage: "arrow.clockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More")

                    if let onDone {
                        Button("Done", action: onDone)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEditSheet, onDismiss: {
            rebuild()
            attemptBackgroundRecovery()
        }) {
            if let game = resolveGameRecord() {
                EditGameDetailsSheet(game: game)
            }
        }
        .sheet(isPresented: $showRecapSheet) {
            let record = resolveGameRecord()
            let whiteElo = analysisResult?.whiteElo ?? (analysisResult?.whiteAccuracy.flatMap { MoveQualityClassifier.estimatedElo(accuracy: $0, plyCount: sans.count) })
            let blackElo = analysisResult?.blackElo ?? (analysisResult?.blackAccuracy.flatMap { MoveQualityClassifier.estimatedElo(accuracy: $0, plyCount: sans.count) })
            ShareRecapSheet(
                title: title,
                whitePlayer: record?.whitePlayer,
                blackPlayer: record?.blackPlayer,
                opening: detectedOpening,
                result: record?.displayResult ?? (try? GameEngine(fen: finalFEN))?.resultToken ?? "*",
                finalFen: finalFEN,
                currentFen: currentDisplayFEN,
                plies: sans.count,
                whiteAccuracy: analysisResult?.whiteAccuracy,
                blackAccuracy: analysisResult?.blackAccuracy,
                whiteElo: whiteElo,
                blackElo: blackElo,
                date: record?.createdAt ?? .now
            )
        }
        .onAppear {
            if activePGN.isEmpty {
                activePGN = pgn
            }
            rebuild()
            loadCachedAnalysis()
        }
        .task(id: activePGN) {
            attemptBackgroundRecovery()
        }
        .onDisappear {
            stopPlayback()
            variationTask?.cancel()
            variationTask = nil
            analysisTask?.cancel()
            analysisTask = nil
            let engine = analysisEngine
            Task { await engine.stop() }
        }
        .confirmationDialog(
            "Moves after this will be removed",
            isPresented: $showPromoteConfirm,
            titleVisibility: .visible
        ) {
            Button("Promote to mainline", role: .destructive) {
                promoteToMainline()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replace the saved game with the current line and clear analysis.")
        }
        .actionToast(message: $toastMessage)
    }

    // MARK: - Layouts

    private var detectedOpening: String? {
        resolveGameRecord()?.openingName ?? OpeningDetector.detect(sans: sans)
    }

    private var portraitBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let opening = detectedOpening, !opening.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption.weight(.bold))
                        Text(opening)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .overlay { Capsule().stroke(Theme.accent.opacity(0.25), lineWidth: 1) }
                    .padding(.top, 4)
                }

                boardRow

                if isMissingInitialPosition {
                    missingInitialPositionBanner
                }

                if variationEngine != nil {
                    variationBanner
                }

                plyControls

                if postGameEnabled {
                    analysisControls
                }

                if AnalysisSettings.effectivePostShowPV, let pv = currentDisplayPVCaption {
                    pvCaptionView(pv)
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

                if AnalysisSettings.effectivePostShowGraph, let result = analysisResult, result.evalSeries.count > 1, variationEngine == nil {
                    EvalGraphView(series: result.evalSeries, selectedIndex: plyIndex) { index in
                        stopPlayback()
                        dismissVariation()
                        plyIndex = index
                    }
                    .padding(.horizontal, 16)
                }

                if let result = analysisResult, !result.plies.isEmpty, variationEngine == nil {
                    MoveQualitySummaryView(
                        result: result,
                        whitePlayerName: resolveGameRecord()?.whitePlayer ?? "White",
                        blackPlayerName: resolveGameRecord()?.blackPlayer ?? "Black",
                        onSelectPly: { ply in
                            stopPlayback()
                            dismissVariation()
                            plyIndex = ply
                        }
                    )
                    .padding(.horizontal, 16)
                }

                MoveListView(
                    sans: sans,
                    selectedPly: (variationEngine == nil && plyIndex > 0) ? plyIndex - 1 : nil,
                    qualities: qualityMap,
                    showsQualityLabels: AnalysisSettings.effectivePostShowLabels,
                    moveTimes: moveTimes.isEmpty ? nil : moveTimes,
                    initialFEN: fastResolvedInitialFen
                ) { index in
                    guard !isMissingInitialPosition else { return }
                    stopPlayback()
                    dismissVariation()
                    plyIndex = index + 1
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 160)
            }
            .padding(.bottom, 24)
        }
    }

    private var landscapeBody: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 12) {
                if let opening = detectedOpening, !opening.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption2.weight(.bold))
                        Text(opening)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .lineLimit(1)
                }

                boardRow
                    .frame(maxHeight: 280)
                if isMissingInitialPosition {
                    missingInitialPositionBanner
                }
                if variationEngine != nil {
                    variationBanner
                }
                plyControls
            }
            .frame(maxWidth: 360)

            ScrollView {
                VStack(spacing: 14) {
                    if postGameEnabled {
                        analysisControls
                    }

                    if AnalysisSettings.effectivePostShowPV, let pv = currentDisplayPVCaption {
                        pvCaptionView(pv)
                    }

                    if isAnalyzing, let progress = analysisProgress {
                        Text("Analyzing \(progress.completed)/\(progress.total)…")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if AnalysisSettings.effectivePostShowGraph, let result = analysisResult, result.evalSeries.count > 1, variationEngine == nil {
                        EvalGraphView(series: result.evalSeries, selectedIndex: plyIndex) { index in
                            stopPlayback()
                            dismissVariation()
                            plyIndex = index
                        }
                    }

                    if let result = analysisResult, !result.plies.isEmpty, variationEngine == nil {
                        MoveQualitySummaryView(
                            result: result,
                            whitePlayerName: resolveGameRecord()?.whitePlayer ?? "White",
                            blackPlayerName: resolveGameRecord()?.blackPlayer ?? "Black",
                            onSelectPly: { ply in
                                stopPlayback()
                                dismissVariation()
                                plyIndex = ply
                            }
                        )
                    }

                    MoveListView(
                        sans: sans,
                        selectedPly: (variationEngine == nil && plyIndex > 0) ? plyIndex - 1 : nil,
                        qualities: qualityMap,
                        showsQualityLabels: AnalysisSettings.effectivePostShowLabels,
                        moveTimes: moveTimes.isEmpty ? nil : moveTimes,
                        initialFEN: fastResolvedInitialFen
                    ) { index in
                        guard !isMissingInitialPosition else { return }
                        stopPlayback()
                        dismissVariation()
                        plyIndex = index + 1
                    }
                    .frame(minHeight: 160)
                }
                .padding(.vertical, 8)
                .padding(.trailing, 16)
            }
        }
        .padding(.leading, 16)
    }

    // MARK: - Board & Eval Bar

    @ViewBuilder
    private var boardRow: some View {
        HStack(alignment: .center, spacing: 10) {
            DigitalBoardView(
                fen: currentDisplayFEN,
                orientation: isFlipped ? .whiteAtTop : .whiteAtBottom,
                lastMove: currentDisplayLastMove,
                bestMove: currentDisplayBestArrow,
                selected: selectedSquare,
                legalDestinations: legalDestinations,
                qualityBadge: currentQualityBadge,
                interactive: true,
                onTap: { square in handleSquareTap(square) }
            )

            if AnalysisSettings.effectivePostShowEvalBar && (isAnalyzing || hasCachedResult || variationEngine != nil) {
                EvalBarView(
                    score: currentDisplayEval,
                    isFlipped: isFlipped,
                    height: isLandscape ? 280 : 320
                )
            }
        }
        .padding(.horizontal, isLandscape ? 0 : 16)
    }

    // MARK: - Variation Banner

    @ViewBuilder
    private var variationBanner: some View {
        if let basePly = variationBasePly {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(Theme.accent)
                        Text("Variation from Move \(basePly)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Button("Return to Game") {
                        dismissVariation()
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.accent)
                }

                if !variationSANs.isEmpty {
                    HStack {
                        Text(formattedVariationSANs)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            undoVariationMove()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(6)
                                .background(Theme.surface, in: Circle())
                                .overlay { Circle().stroke(Theme.border, lineWidth: 1) }
                        }
                        .accessibilityLabel("Undo variation move")
                    }
                }

                if canPromoteToMainline {
                    Button {
                        showPromoteConfirm = true
                    } label: {
                        Label("Promote to mainline", systemImage: "arrow.up.to.line")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(Theme.onAccent)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .accessibilityLabel("Promote variation to mainline")
                }
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
            }
            .padding(.horizontal, isLandscape ? 0 : 16)
        }
    }

    private var missingInitialPositionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Legacy Mid-Game Match")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Starting position wasn't recorded. Set starting FEN to replay moves.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                showEditSheet = true
            } label: {
                Text("Set FEN")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityLabel("Set starting board position")
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        }
        .padding(.horizontal, isLandscape ? 0 : 16)
    }

    private var formattedVariationSANs: String {
        guard let basePly = variationBasePly else { return "" }
        var startMoveNumber = 1
        var startsWithBlack = false
        if let fen = fastResolvedInitialFen {
            let parts = fen.split(separator: " ")
            if parts.count >= 2 {
                startsWithBlack = (parts[1] == "b")
            }
            if parts.count >= 6, let num = Int(parts[5]), num > 0 {
                startMoveNumber = num
            }
        }
        var tokens: [String] = []
        for (i, san) in variationSANs.enumerated() {
            let ply = basePly + i
            let isBlack = startsWithBlack ? (ply % 2 == 0) : (ply % 2 != 0)
            let moveNum = startMoveNumber + (startsWithBlack ? (ply + 1) / 2 : ply / 2)
            if !isBlack {
                tokens.append("\(moveNum). \(san)")
            } else if i == 0 {
                tokens.append("\(moveNum)... \(san)")
            } else {
                tokens.append(san)
            }
        }
        return tokens.joined(separator: " ")
    }

    // MARK: - Playback Controls

    private var plyControls: some View {
        VStack(spacing: 8) {
            Text(plyCaption)
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                CircularButton(
                    icon: "arrow.up.arrow.down",
                    title: "Flip",
                    size: 40
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isFlipped.toggle()
                    }
                }
                .accessibilityLabel(isFlipped ? "Flip board to White" : "Flip board to Black")

                CircularButton(
                    icon: "backward.end",
                    title: "First",
                    size: 40,
                    isDisabled: isMissingInitialPosition || plyIndex == 0 || variationEngine != nil
                ) {
                    stopPlayback()
                    plyIndex = 0
                    clearSelection()
                }
                .accessibilityLabel("First move")

                CircularButton(
                    icon: "chevron.backward",
                    title: "Prev",
                    size: 40,
                    isDisabled: isMissingInitialPosition || plyIndex == 0 || variationEngine != nil
                ) {
                    stopPlayback()
                    plyIndex = max(plyIndex - 1, 0)
                    clearSelection()
                    ChessAudioFeedback.playMove()
                }
                .accessibilityLabel("Previous move")

                CircularButton(
                    icon: isPlaying ? "pause.fill" : "play.fill",
                    title: isPlaying ? "Pause" : "Play",
                    size: 48,
                    isDisabled: isMissingInitialPosition || sans.isEmpty || variationEngine != nil
                ) {
                    togglePlayback()
                }
                .accessibilityLabel(isPlaying ? "Pause playback" : "Play game")

                CircularButton(
                    icon: "chevron.forward",
                    title: "Next",
                    size: 40,
                    isDisabled: isMissingInitialPosition || plyIndex >= sans.count || variationEngine != nil
                ) {
                    stopPlayback()
                    plyIndex = min(plyIndex + 1, sans.count)
                    clearSelection()
                    ChessAudioFeedback.playMove()
                }
                .accessibilityLabel("Next move")

                CircularButton(
                    icon: "forward.end",
                    title: "Last",
                    size: 40,
                    isDisabled: isMissingInitialPosition || plyIndex >= sans.count || variationEngine != nil
                ) {
                    stopPlayback()
                    plyIndex = sans.count
                    clearSelection()
                }
                .accessibilityLabel("Last move")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, isLandscape ? 0 : 16)
    }

    private func pvCaptionView(_ pv: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(pv)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
        .padding(.horizontal, isLandscape ? 0 : 16)
    }

    @ViewBuilder
    private var analysisControls: some View {
        VStack(spacing: 8) {
            if !hasCachedResult, !isAnalyzing {
                Button {
                    startAnalysis()
                } label: {
                    Text("Analyze")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(sans.isEmpty || isMissingInitialPosition)
                .padding(.horizontal, isLandscape ? 0 : 16)
                .accessibilityLabel("Analyze")
            }
        }
    }

    // MARK: - Interactive Move Handling & Branching

    private func handleSquareTap(_ square: ChessSquare) {
        guard !isMissingInitialPosition else { return }
        stopPlayback()

        // If tapping currently selected square, deselect
        if selectedSquare == square {
            clearSelection()
            return
        }

        // If a piece was already selected and tapped square is a legal destination:
        if let start = selectedSquare, legalDestinations.contains(square) {
            executeMove(from: start, to: square)
            return
        }

        // Otherwise, select piece at square if valid
        selectPiece(at: square)
    }

    private func selectPiece(at square: ChessSquare) {
        let fen = currentDisplayFEN
        guard let engine = try? GameEngine(fen: fen) else {
            clearSelection()
            return
        }

        let pieces = FenCodec.parsePieces(fen)
        guard let piece = pieces[square], piece != .empty else {
            clearSelection()
            return
        }

        guard let pieceColor = piece.pieceColor else {
            clearSelection()
            return
        }
        guard pieceColor == engine.board.position.sideToMove else {
            clearSelection()
            return
        }

        let destinations = engine.legalDestinations(for: square)
        if !destinations.isEmpty {
            selectedSquare = square
            legalDestinations = destinations
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            clearSelection()
        }
    }

    private func executeMove(from: ChessSquare, to: ChessSquare) {
        clearSelection()

        // Check if on mainline replay
        if variationEngine == nil {
            let fen = currentFEN
            guard let trialEngine = try? GameEngine(fen: fen),
                  let moveSan = try? trialEngine.executeMove(from: from, to: to) else { return }

            // If move matches mainline SAN, just advance mainline ply
            if plyIndex < sans.count && sans[plyIndex] == moveSan {
                plyIndex += 1
                ChessAudioFeedback.playMove()
                return
            }

            // Divergence: branch into an in-memory exploration variation!
            variationBasePly = plyIndex
            variationEngine = trialEngine
            variationSANs = [moveSan]
            variationEval = currentEval
            ChessAudioFeedback.playMove()
            analyzeVariation(fen: trialEngine.fen)
        } else if let engine = variationEngine {
            // Already exploring a variation
            guard let moveSan = try? engine.executeMove(from: from, to: to) else { return }
            variationSANs.append(moveSan)
            ChessAudioFeedback.playMove()
            analyzeVariation(fen: engine.fen)
        }
    }

    private func undoVariationMove() {
        guard let engine = variationEngine else { return }
        if variationSANs.count > 1 {
            try? engine.undo()
            variationSANs.removeLast()
            ChessAudioFeedback.playMove()
            analyzeVariation(fen: engine.fen)
        } else {
            dismissVariation()
        }
    }

    private func dismissVariation() {
        variationTask?.cancel()
        variationTask = nil
        variationEngine = nil
        variationBasePly = nil
        variationSANs = []
        variationEval = nil
        variationBestArrow = nil
        variationPVCaption = nil
        clearSelection()
    }

    private var canPromoteToMainline: Bool {
        resolveGameRecord() != nil && variationEngine != nil && !variationSANs.isEmpty
    }

    /// Persist the in-memory variation as the game's mainline.
    private func promoteToMainline() {
        guard let record = resolveGameRecord(),
              let basePly = variationBasePly,
              variationEngine != nil,
              !variationSANs.isEmpty else { return }

        let newSans = Array(sans.prefix(basePly)) + variationSANs

        let starting = fastResolvedInitialFen ?? FenCodec.standard
        let rebuilt: GameEngine
        if let loaded = try? GameEngine(fen: starting) {
            rebuilt = loaded
        } else {
            rebuilt = GameEngine()
        }
        for san in newSans {
            do {
                try rebuilt.apply(san: san)
            } catch {
                return
            }
        }

        let targetPly = newSans.count
        activePGN = rebuilt.pgn
        record.pgn = rebuilt.pgn
        record.finalFen = rebuilt.fen
        record.openingName = OpeningDetector.detect(sans: newSans)
        if record.moveTimes.count > targetPly {
            record.moveTimes = Array(record.moveTimes.prefix(targetPly))
        } else if !moveTimes.isEmpty {
            record.moveTimes = Array(moveTimes.prefix(targetPly))
        }
        var times = record.moveTimes
        while times.count < targetPly {
            times.append(0)
        }
        record.moveTimes = times
        record.clearPersistedAnalysis()
        try? modelContext.save()

        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisResult = nil
        analysisProgress = nil
        analysisMessage = nil
        cachedSpeedRaw = nil

        dismissVariation()
        stopPlayback()
        rebuild()
        plyIndex = min(targetPly, sans.count)
    }

    private func clearSelection() {
        selectedSquare = nil
        legalDestinations = []
    }

    private func analyzeVariation(fen: String) {
        variationTask?.cancel()
        // Retain previous variationEval so the eval bar doesn't bounce to 0.0 default while engine thinks
        variationBestArrow = nil
        variationPVCaption = nil

        let engine = analysisEngine
        variationTask = Task {
            guard let eval = await engine.analyze(.replay(fen: fen)) else { return }
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.variationEval = eval.score
                }
                self.variationBestArrow = eval.bestArrow
                if !eval.pvUCI.isEmpty {
                    self.variationPVCaption = PVFormatter.format(fen: fen, uciMoves: eval.pvUCI)
                }
            }
        }
    }

    // MARK: - Playback Timer

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            dismissVariation()
            startPlayback()
        }
    }

    private func startPlayback() {
        guard !isMissingInitialPosition else { return }
        if plyIndex >= sans.count {
            plyIndex = 0
        }
        isPlaying = true
        playbackTimer?.cancel()
        playbackTimer = Task { @MainActor in
            while !Task.isCancelled && isPlaying && plyIndex < sans.count {
                try? await Task.sleep(for: .milliseconds(900))
                if Task.isCancelled || !isPlaying { break }
                plyIndex += 1
                ChessAudioFeedback.playMove()
            }
            isPlaying = false
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.cancel()
        playbackTimer = nil
    }

    // MARK: - Computed Properties

    private var currentDisplayFEN: String {
        variationEngine?.fen ?? currentFEN
    }

    private var currentFEN: String {
        if isMissingInitialPosition {
            return resolveGameRecord()?.finalFen ?? fastResolvedInitialFen ?? FenCodec.standard
        }
        guard plyIndex >= 0, plyIndex < fens.count else {
            return fastResolvedInitialFen ?? FenCodec.standard
        }
        return fens[plyIndex]
    }

    private var finalFEN: String {
        resolveGameRecord()?.finalFen ?? fens.last ?? fastResolvedInitialFen ?? FenCodec.standard
    }

    private var currentDisplayLastMove: (from: ChessSquare, to: ChessSquare)? {
        if let variationEngine {
            return variationEngine.lastMoveSquares
        }
        return lastMoveHighlight
    }

    private var lastMoveHighlight: (from: ChessSquare, to: ChessSquare)? {
        guard !isMissingInitialPosition, plyIndex > 0, plyIndex <= sans.count else { return nil }
        do {
            let starting = fastResolvedInitialFen ?? FenCodec.standard
            let engine = (try? GameEngine(fen: starting)) ?? GameEngine()
            for san in sans.prefix(plyIndex) {
                try engine.apply(san: san)
            }
            return engine.lastMoveSquares
        } catch {
            return nil
        }
    }

    private var currentDisplayEval: EvaluationScore? {
        if variationEngine != nil {
            return variationEval ?? currentEval
        }
        return currentEval
    }

    private var currentEval: EvaluationScore? {
        guard let result = analysisResult else { return nil }
        if plyIndex < result.evalSeries.count {
            return result.evalSeries[plyIndex]
        }
        return result.plies.last?.playedScore
    }

    private var currentDisplayBestArrow: BoardArrow? {
        if variationEngine != nil {
            return variationBestArrow
        }
        return currentBestArrow
    }

    private var currentBestArrow: BoardArrow? {
        guard AnalysisSettings.effectivePostShowArrow else { return nil }
        guard plyIndex < sans.count, let result = analysisResult else { return nil }
        return result.plies.first(where: { $0.plyIndex == plyIndex })?.best.bestArrow
    }

    private var currentDisplayPVCaption: String? {
        if variationEngine != nil {
            return variationPVCaption
        }
        return currentPVCaption
    }

    private var currentPVCaption: String? {
        guard plyIndex < sans.count, let result = analysisResult,
              let ply = result.plies.first(where: { $0.plyIndex == plyIndex }) else { return nil }
        let formatted = PVFormatter.format(fen: currentFEN, uciMoves: ply.best.pvUCI)
        guard !formatted.isEmpty else { return nil }
        return formatted
    }

    private var currentQualityBadge: MoveQuality? {
        guard variationEngine == nil, plyIndex > 0 else { return nil }
        return qualityMap[plyIndex - 1]
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
        if isMissingInitialPosition {
            return "\(sans.count) moves recorded (starting position needed)"
        }
        if variationEngine != nil {
            return "Branch · \(variationSANs.count) moves"
        }
        if plyIndex == 0 { return "Start" }
        var text = "\(plyIndex)/\(sans.count)  \(sans[plyIndex - 1])"
        if AnalysisSettings.effectivePostShowLabels,
           let quality = qualityMap[plyIndex - 1],
           !quality.glyph.isEmpty {
            text += " \(quality.glyph)"
        }
        return text
    }

    // MARK: - Rebuild & Cache

    private var fastResolvedInitialFen: String? {
        if let currentInitialFen, !currentInitialFen.isEmpty { return currentInitialFen }
        if let initialFen, !initialFen.isEmpty { return initialFen }
        if let record = resolveGameRecord(), let fen = record.initialFen, !fen.isEmpty { return fen }
        let source = activePGN.isEmpty ? pgn : activePGN
        if let extracted = PGNMoveList.extractFEN(from: source) { return extracted }
        if let record = resolveGameRecord(), let analysis = record.loadPersistedAnalysis(), let firstFen = analysis.result.plies.first?.fenBefore, !firstFen.isEmpty {
            record.initialFen = firstFen
            try? modelContext.save()
            return firstFen
        }
        return nil
    }

    private func rebuild() {
        let source = activePGN.isEmpty ? pgn : activePGN
        let originalSans = PGNMoveList.sans(from: source)
        sans = originalSans

        if let starting = fastResolvedInitialFen {
            isMissingInitialPosition = false
            var frames = [starting]
            let engine: GameEngine
            if let loaded = try? GameEngine(fen: starting) {
                engine = loaded
            } else {
                engine = GameEngine()
            }
            for san in originalSans {
                do {
                    try engine.apply(san: san)
                    frames.append(engine.fen)
                } catch {
                    break
                }
            }
            fens = frames
            plyIndex = min(plyIndex, max(0, frames.count - 1))
        } else {
            // No explicit initial FEN known yet. Try simulating from standard starting position.
            var frames = [FenCodec.standard]
            let engine = GameEngine()
            var simulatedAll = true
            for san in originalSans {
                do {
                    try engine.apply(san: san)
                    frames.append(engine.fen)
                } catch {
                    simulatedAll = false
                    break
                }
            }

            if simulatedAll && !originalSans.isEmpty {
                isMissingInitialPosition = false
                fens = frames
                plyIndex = min(plyIndex, sans.count)
            } else {
                // Cannot legally apply moves from standard starting position.
                // This is a legacy game started mid-game without recorded initial FEN.
                isMissingInitialPosition = true
                let fallbackBoard = resolveGameRecord()?.finalFen ?? FenCodec.standard
                fens = [fallbackBoard]
                plyIndex = 0
            }
        }
        reloadMoveTimes()
    }

    private func attemptBackgroundRecovery() {
        guard isMissingInitialPosition,
              !sans.isEmpty,
              sans.count <= 6,
              let record = resolveGameRecord() else { return }

        let finalFen = record.finalFen
        guard !finalFen.isEmpty else { return }

        let currentSans = sans
        Task.detached(priority: .background) {
            if let solved = RetrogradePositionSolver.solveInitialFEN(
                sans: currentSans,
                finalFen: finalFen,
                maxNodes: 200
            ) {
                await MainActor.run {
                    guard self.isMissingInitialPosition else { return }
                    self.currentInitialFen = solved
                    if let rec = self.resolveGameRecord(), rec.initialFen == nil {
                        rec.initialFen = solved
                        try? self.modelContext.save()
                    }
                    self.rebuild()
                }
            }
        }
    }

    private func reloadMoveTimes() {
        if let record = resolveGameRecord() {
            var times = record.moveTimes
            if times.isEmpty {
                times = PGNMoveList.emtSeconds(from: record.pgnWithHeaders)
            }
            if times.isEmpty {
                times = PGNMoveList.emtSeconds(from: activePGN.isEmpty ? pgn : activePGN)
            }
            if times.count > sans.count {
                times = Array(times.prefix(sans.count))
            }
            moveTimes = times
        } else {
            let fromPGN = PGNMoveList.emtSeconds(from: activePGN.isEmpty ? pgn : activePGN)
            moveTimes = fromPGN.count == sans.count ? fromPGN : Array(fromPGN.prefix(sans.count))
        }
    }

    private func resolveGameRecord() -> GameRecord? {
        guard let gamePersistentID else { return nil }
        return modelContext.model(for: gamePersistentID) as? GameRecord
    }

    private func loadCachedAnalysis() {
        guard postGameEnabled, let persisted = resolveGameRecord()?.loadPersistedAnalysis() else {
            return
        }
        analysisResult = persisted.result
        cachedSpeedRaw = persisted.speedRaw
        analysisMessage = nil
    }

    private func startAnalysis() {
        guard AnalysisSettings.postGameEnabled else { return }
        guard !sans.isEmpty, fens.count == sans.count + 1 else {
            analysisMessage = nil
            return
        }
        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        analysisProgress = GameAnalyzer.Progress(completed: 0, total: sans.count)
        if var existing = analysisResult {
            existing.whiteAccuracy = nil
            existing.blackAccuracy = nil
            existing.plies = []
            existing.evalSeries = [.centipawns(0)]
            analysisResult = existing
        } else {
            analysisResult = GameAnalysisResult.empty
        }

        let engine = analysisEngine
        let sansCopy = sans
        let fensCopy = fens
        let speedRaw = AnalysisSettings.speed.rawValue

        analysisTask = Task {
            let analyzer = GameAnalyzer(engine: engine)
            do {
                let result = try await analyzer.analyze(sans: sansCopy, fens: fensCopy) { ply, series, progress in
                    Task { @MainActor in
                        var partial = analysisResult ?? .empty
                        if ply.plyIndex < partial.plies.count {
                            partial.plies[ply.plyIndex] = ply
                        } else {
                            partial.plies.append(ply)
                        }
                        partial.evalSeries = series
                        partial.whiteAccuracy = nil
                        partial.blackAccuracy = nil
                        analysisResult = partial
                        analysisProgress = progress
                    }
                }
                let availability = await engine.availability
                await MainActor.run {
                    isAnalyzing = false
                    analysisProgress = nil
                    if Task.isCancelled { return }
                    if result.plies.isEmpty {
                        analysisMessage = availability.userMessage
                            ?? (availability == .ready ? nil : "Analysis unavailable.")
                    } else {
                        analysisResult = result
                        analysisMessage = nil
                        cachedSpeedRaw = speedRaw
                        persistCompletedAnalysis(result, speedRaw: speedRaw)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isAnalyzing = false
                    analysisProgress = nil
                }
                await engine.stop()
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    analysisProgress = nil
                    analysisMessage = "Analysis failed."
                }
            }
        }
    }

    private func persistCompletedAnalysis(_ result: GameAnalysisResult, speedRaw: String) {
        guard let record = resolveGameRecord() else { return }
        let persisted = PersistedGameAnalysis(
            schemaVersion: PersistedGameAnalysis.currentSchemaVersion,
            speedRaw: speedRaw,
            analyzedAt: .now,
            result: result
        )
        record.savePersistedAnalysis(persisted)
        try? modelContext.save()
    }

    private var exportPGNString: String {
        if let record = resolveGameRecord() {
            return record.pgnWithHeaders
        }
        if !activePGN.isEmpty {
            return activePGN
        }
        return pgn
    }

    private var pgnShareURL: URL {
        (try? PGNShareFile.write(pgn: exportPGNString, title: title))
            ?? FileManager.default.temporaryDirectory.appending(path: "game.pgn")
    }
}

#Preview {
    NavigationStack {
        ReplayView(pgn: "1. e4 e5 2. Nf3", title: "Game · Sep 9")
    }
}
