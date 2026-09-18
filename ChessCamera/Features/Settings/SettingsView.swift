import SwiftUI

struct SettingsView: View {
    @AppStorage(FastReplySettings.key) private var detectFastReplies = true
    @AppStorage(AutoResumeSettings.key) private var autoResume = false
    @AppStorage(SpeechSettings.key) private var speakMoves = false
    @AppStorage(BoardAppearance.styleKey) private var styleRaw = BoardAppearance.defaultStyle.rawValue
    @AppStorage(DetectionSettings.yoloConfidenceKey) private var yoloConfidenceRaw =
        DetectionSettings.yoloConfidenceDefault
    @AppStorage(DetectionSettings.classifierConfidenceKey) private var classifierConfidenceRaw =
        DetectionSettings.classifierConfidenceDefault
    @AppStorage(DebugOverlaySettings.showYoloDotsKey) private var showYoloDots = true
    @AppStorage(DebugOverlaySettings.showCaptureDiagnosticsKey) private var showCaptureDiagnostics = true
    @AppStorage(DebugOverlaySettings.showBoardGridKey) private var showBoardGrid = true
    @AppStorage(DebugOverlaySettings.showOccupancyOverlayKey) private var showOccupancyOverlay = true
    @AppStorage(DebugOverlaySettings.showPieceBoxesKey) private var showPieceBoxes = false

    @AppStorage(AnalysisSettings.liveHintsKey) private var liveHints = false
    @AppStorage(AnalysisSettings.liveShowEvalKey) private var liveShowEval = true
    @AppStorage(AnalysisSettings.liveShowArrowKey) private var liveShowArrow = true
    @AppStorage(AnalysisSettings.postGameKey) private var postGame = true
    @AppStorage(AnalysisSettings.postShowEvalBarKey) private var postShowEvalBar = true
    @AppStorage(AnalysisSettings.postShowArrowKey) private var postShowArrow = true
    @AppStorage(AnalysisSettings.postShowPVKey) private var postShowPV = true
    @AppStorage(AnalysisSettings.postShowLabelsKey) private var postShowLabels = true
    @AppStorage(AnalysisSettings.postShowAccuracyKey) private var postShowAccuracy = true
    @AppStorage(AnalysisSettings.postShowGraphKey) private var postShowGraph = true
    @AppStorage(AnalysisSettings.speedKey) private var speedRaw = AnalysisSpeed.balanced.rawValue

    @State private var showAppearance = false
    @State private var showStockfishLicense = false

    private var selectedStyle: BoardStyle {
        BoardStyle(rawValue: styleRaw) ?? BoardAppearance.defaultStyle
    }

    private var analysisSpeed: Binding<String> {
        Binding(
            get: { speedRaw },
            set: { speedRaw = $0 }
        )
    }

    private var settleMilliseconds: Binding<Int> {
        Binding(
            get: { SettleSettings.milliseconds },
            set: { SettleSettings.milliseconds = $0 }
        )
    }

    private var yoloConfidence: Binding<Double> {
        Binding(
            get: { DetectionSettings.clamp(yoloConfidenceRaw, to: DetectionSettings.yoloConfidenceRange) },
            set: { yoloConfidenceRaw = DetectionSettings.clamp($0, to: DetectionSettings.yoloConfidenceRange) }
        )
    }

    private var classifierConfidence: Binding<Double> {
        Binding(
            get: {
                DetectionSettings.clamp(
                    classifierConfidenceRaw,
                    to: DetectionSettings.classifierConfidenceRange
                )
            },
            set: {
                classifierConfidenceRaw = DetectionSettings.clamp(
                    $0,
                    to: DetectionSettings.classifierConfidenceRange
                )
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                settingsSection(title: "Detection") {
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "Fast replies",
                            subtitle: "Record both players when one replies before the board settles.",
                            systemImage: "arrow.left.arrow.right",
                            isOn: $detectFastReplies
                        )
                        divider
                        toggleRow(
                            title: "Auto-resume",
                            subtitle: "Automatically resume recording 1 second after an unrecognized move.",
                            systemImage: "arrow.clockwise",
                            isOn: $autoResume
                        )
                    }
                }

                settingsSection(title: "Playback") {
                    toggleRow(
                        title: "Speak moves",
                        subtitle: "Announce each committed move out loud.",
                        systemImage: "speaker.wave.2",
                        isOn: $speakMoves
                    )
                }

                settingsSection(title: "Analysis") {
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "Live hints",
                            subtitle: "Show eval and a best-move arrow on the digital board while recording. Uses more battery.",
                            systemImage: "lightbulb",
                            isOn: $liveHints
                        )
                        if liveHints {
                            divider
                            toggleRow(
                                title: "Show eval",
                                subtitle: "Display the Stockfish score next to the live board.",
                                systemImage: "plusminus",
                                isOn: $liveShowEval
                            )
                            divider
                            toggleRow(
                                title: "Best-move arrow",
                                subtitle: "Draw the engine’s suggested move on the digital board.",
                                systemImage: "arrow.up.right",
                                isOn: $liveShowArrow
                            )
                        }
                        divider
                        toggleRow(
                            title: "Post-game analysis",
                            subtitle: "Analyze saved games in Replay with eval, labels, and accuracy.",
                            systemImage: "chart.line.uptrend.xyaxis",
                            isOn: $postGame
                        )
                        if postGame {
                            divider
                            toggleRow(
                                title: "Eval bar",
                                subtitle: "Show a White/Black eval bar beside the replay board.",
                                systemImage: "chart.bar.fill",
                                isOn: $postShowEvalBar
                            )
                            divider
                            toggleRow(
                                title: "Best-move arrow",
                                subtitle: "Highlight the engine’s best move at the current ply.",
                                systemImage: "arrow.up.right",
                                isOn: $postShowArrow
                            )
                            divider
                            toggleRow(
                                title: "Principal variation",
                                subtitle: "Show the engine’s main line under the board.",
                                systemImage: "list.number",
                                isOn: $postShowPV
                            )
                            divider
                            toggleRow(
                                title: "Move labels",
                                subtitle: "Mark inaccuracies, mistakes, and blunders in the move list.",
                                systemImage: "exclamationmark.bubble",
                                isOn: $postShowLabels
                            )
                            divider
                            toggleRow(
                                title: "Accuracy %",
                                subtitle: "Show White and Black accuracy after analysis finishes.",
                                systemImage: "percent",
                                isOn: $postShowAccuracy
                            )
                            divider
                            toggleRow(
                                title: "Eval graph",
                                subtitle: "Plot evaluation across the game; tap to jump to a ply.",
                                systemImage: "waveform.path.ecg",
                                isOn: $postShowGraph
                            )
                        }
                        divider
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                settingIcon("gauge.with.dots.needle.33percent")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Analysis speed")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("How long Stockfish thinks per position in Replay.")
                                        .font(.callout)
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Picker("Analysis speed", selection: analysisSpeed) {
                                ForEach(AnalysisSpeed.allCases) { speed in
                                    Text(speed.title).tag(speed.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Analysis speed")
                        }
                        .padding(16)
                        divider
                        Button {
                            showStockfishLicense = true
                        } label: {
                            HStack(spacing: 12) {
                                settingIcon("doc.text")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("About Stockfish")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Analysis by Stockfish 17 (GPLv3).")
                                        .font(.callout)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("About Stockfish")
                    }
                }

                settingsSection(title: "Board") {
                    Button {
                        showAppearance = true
                    } label: {
                        HStack(spacing: 12) {
                            settingIcon("checkerboard.rectangle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Appearance")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(selectedStyle.title)
                                    .font(.callout)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Board appearance, \(selectedStyle.title)")
                }

                settingsSection(title: "Recording") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            settingIcon("timer")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Settle wait")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("How long the board must stay still before a move is committed.")
                                    .font(.callout)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Picker("Settle wait", selection: settleMilliseconds) {
                            Text("300 ms").tag(300)
                            Text("600 ms").tag(600)
                            Text("900 ms").tag(900)
                            Text("1.5 s").tag(1500)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Settle wait")
                    }
                    .padding(16)
                }

                settingsSection(title: "Developer") {
                    VStack(spacing: 0) {
                        Text("Field-tuning overlays and detection cutoffs. Chess rules stay in Detection and Recording.")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)

                        sliderRow(
                            title: "Piece confidence",
                            subtitle: "Ignore YOLO detections below this score.",
                            systemImage: "viewfinder",
                            value: yoloConfidence,
                            range: DetectionSettings.yoloConfidenceRange
                        )
                        divider
                        sliderRow(
                            title: "Classifier confidence",
                            subtitle: "Treat confirm-start square labels below this score as empty.",
                            systemImage: "square.grid.3x3",
                            value: classifierConfidence,
                            range: DetectionSettings.classifierConfidenceRange
                        )
                        divider
                        toggleRow(
                            title: "YOLO debug dots",
                            subtitle: "Mark each detected piece base on the camera and board preview.",
                            systemImage: "circle.fill",
                            isOn: $showYoloDots
                        )
                        divider
                        toggleRow(
                            title: "Capture diagnostics",
                            subtitle: "Show the live phase, Hamming, and last-move debug line.",
                            systemImage: "text.alignleft",
                            isOn: $showCaptureDiagnostics
                        )
                        divider
                        toggleRow(
                            title: "Board grid",
                            subtitle: "Draw files and ranks over the locked board while recording.",
                            systemImage: "grid",
                            isOn: $showBoardGrid
                        )
                        divider
                        toggleRow(
                            title: "Occupancy overlay",
                            subtitle: "Show occupied squares on the warped board preview.",
                            systemImage: "circle.grid.3x3",
                            isOn: $showOccupancyOverlay
                        )
                        divider
                        toggleRow(
                            title: "Piece boxes",
                            subtitle: "Draw YOLO bounding boxes on the live camera and board preview.",
                            systemImage: "rectangle.dashed",
                            isOn: $showPieceBoxes
                        )
                        divider
                        Button(action: resetDeveloperSettings) {
                            HStack(spacing: 12) {
                                settingIcon("arrow.counterclockwise")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reset developer settings")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Restore detection cutoffs and overlay toggles.")
                                        .font(.callout)
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset developer settings")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sheet(isPresented: $showAppearance) {
            BoardAppearanceSheet()
        }
        .sheet(isPresented: $showStockfishLicense) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Stockfish 17")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(
                            """
                            Takes uses the Stockfish chess engine for optional on-device analysis. Stockfish is free software licensed under the GNU General Public License version 3 (GPLv3).

                            Source: https://github.com/official-stockfish/Stockfish

                            The Swift UCI bridge is ChessKitEngine (MIT): https://github.com/chesskit-app/chesskit-engine

                            Distributing this app with Stockfish linked in-process generally requires offering corresponding source under GPLv3. This Academy prototype ships Stockfish for local analysis; review licensing before App Store release.
                            """
                        )
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                    }
                    .padding(16)
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("About Stockfish")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showStockfishLicense = false }
                    }
                }
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
            content()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                settingIcon(systemImage)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
        .padding(16)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private func sliderRow(
        title: String,
        subtitle: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                settingIcon(systemImage)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Text("\(Int((value.wrappedValue * 100).rounded()))%")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Slider(value: value, in: range, step: 0.01)
                .tint(Theme.accent)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) percent")
        }
        .padding(16)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border.opacity(0.45))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func resetDeveloperSettings() {
        DetectionSettings.resetToDefaults()
        DebugOverlaySettings.resetToDefaults()
        yoloConfidenceRaw = DetectionSettings.yoloConfidenceDefault
        classifierConfidenceRaw = DetectionSettings.classifierConfidenceDefault
        showYoloDots = true
        showCaptureDiagnostics = true
        showBoardGrid = true
        showOccupancyOverlay = true
        showPieceBoxes = false
    }

    private func settingIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
