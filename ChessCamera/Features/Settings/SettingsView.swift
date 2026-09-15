import SwiftUI

struct SettingsView: View {
    @AppStorage(FastReplySettings.key) private var detectFastReplies = true
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
    @State private var showAppearance = false

    private var selectedStyle: BoardStyle {
        BoardStyle(rawValue: styleRaw) ?? BoardAppearance.defaultStyle
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
                    toggleRow(
                        title: "Fast replies",
                        subtitle: "Record both players when one replies before the board settles.",
                        systemImage: "arrow.left.arrow.right",
                        isOn: $detectFastReplies
                    )
                }

                settingsSection(title: "Playback") {
                    toggleRow(
                        title: "Speak moves",
                        subtitle: "Announce each committed move out loud.",
                        systemImage: "speaker.wave.2",
                        isOn: $speakMoves
                    )
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
