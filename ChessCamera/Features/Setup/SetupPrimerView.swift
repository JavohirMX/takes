import SwiftUI

struct SetupPrimerView: View {
    var onContinue: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Set up once")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)

                        primerRow(
                            symbol: "checkerboard.rectangle",
                            title: "One set, standard start",
                            body: "Use one chess set, indoor light, and the standard starting position."
                        )
                        primerRow(
                            symbol: "iphone.rear.facing.camera",
                            title: "See every square",
                            body: "Mount the iPhone so every square is visible. A tripod is best; a stand at an angle is fine."
                        )
                        primerRow(
                            symbol: "hand.raised",
                            title: "Keep the phone still",
                            body: "Do not move the phone during the game. Pause off the board between moves. The app waits until the position is still."
                        )
                        primerRow(
                            symbol: "arrow.uturn.backward",
                            title: "Fix only when needed",
                            body: "If a move is wrong, tap it and fix. You do not need to confirm every move."
                        )
                    }
                    .padding(16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Set up the board", action: onContinue)
                    .padding(16)
                    .background(Theme.background)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func primerRow(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(body)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

#Preview {
    SetupPrimerView(onContinue: {}, onDismiss: {})
}
