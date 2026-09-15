import SwiftUI

struct SettingsView: View {
    @AppStorage(FastReplySettings.key) private var detectFastReplies = true
    @AppStorage(SpeechSettings.key) private var speakMoves = false
    @AppStorage(BoardAppearance.styleKey) private var styleRaw = BoardAppearance.defaultStyle.rawValue
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
