import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "checkerboard.rectangle")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)

                    Text("Games you record will appear here.")
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    PrimaryButton(title: "New Game")
                        .padding(.horizontal, 16)

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Chess Camera")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("New Game")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

#Preview("History empty") {
    HistoryView()
}
