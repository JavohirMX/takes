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
                            title: "See every square",
                            body: "Mount the phone so the whole board is visible. A stand is fine; the camera can be at an angle."
                        )
                        primerRow(
                            symbol: "dot.viewfinder",
                            title: "Put the four corners on the board",
                            body: "Drag the numbered handles onto the four corners. The square view should show each piece inside its square."
                        )
                        primerRow(
                            symbol: "arrow.up.left.and.arrow.down.right",
                            title: "Nudge the phone",
                            body: "The grid should follow small camera movement. If it slips, drag the corners again."
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
