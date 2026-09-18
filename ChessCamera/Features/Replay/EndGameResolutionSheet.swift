import SwiftUI

enum GameConclusionOutcome: String, CaseIterable, Identifiable {
    case whiteResigned = "White resigned"
    case blackResigned = "Black resigned"
    case agreedDraw = "Agreed draw"
    case whiteTime = "Black ran out of time"
    case blackTime = "White ran out of time"
    case friendlyStop = "Game ended"

    var id: String { rawValue }

    var resultToken: String {
        switch self {
        case .whiteResigned, .blackTime: "0-1"
        case .blackResigned, .whiteTime: "1-0"
        case .agreedDraw: "½-½"
        case .friendlyStop: "*"
        }
    }

    var icon: String {
        switch self {
        case .whiteResigned, .blackResigned: "flag.fill"
        case .agreedDraw: "equal.circle.fill"
        case .whiteTime, .blackTime: "clock.fill"
        case .friendlyStop: "stop.circle.fill"
        }
    }
}

struct EndGameResolutionSheet: View {
    let onConfirm: (GameConclusionOutcome, String?, String?) -> Void
    let onCancel: () -> Void

    @State private var selectedOutcome: GameConclusionOutcome = .friendlyStop
    @State private var whitePlayer: String = ""
    @State private var blackPlayer: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("How did the game end?")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    VStack(spacing: 8) {
                        ForEach(GameConclusionOutcome.allCases) { outcome in
                            Button {
                                selectedOutcome = outcome
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: outcome.icon)
                                        .foregroundStyle(selectedOutcome == outcome ? Theme.accent : Theme.textSecondary)
                                        .frame(width: 24, height: 24)
                                    Text(outcome.rawValue)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(outcome.resultToken)
                                        .font(.callout.monospaced().weight(.semibold))
                                        .foregroundStyle(selectedOutcome == outcome ? Theme.accent : Theme.textSecondary)
                                    if selectedOutcome == outcome {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(14)
                                .background(
                                    selectedOutcome == outcome ? Theme.accent.opacity(0.15) : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            selectedOutcome == outcome ? Theme.accent : Theme.border.opacity(0.4),
                                            lineWidth: selectedOutcome == outcome ? 1.5 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .background(Theme.border.opacity(0.5))

                    Text("Player Names (Optional)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    VStack(spacing: 12) {
                        TextField("White player", text: $whitePlayer)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border.opacity(0.5), lineWidth: 1))
                            .foregroundStyle(Theme.textPrimary)

                        TextField("Black player", text: $blackPlayer)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border.opacity(0.5), lineWidth: 1))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Save and End Game") {
                            let white = whitePlayer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : whitePlayer.trimmingCharacters(in: .whitespaces)
                            let black = blackPlayer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : blackPlayer.trimmingCharacters(in: .whitespaces)
                            onConfirm(selectedOutcome, white, black)
                        }

                        Button("Keep Playing", action: onCancel)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("End Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }
}
