import SwiftUI

struct GameOverView: View {
    @Bindable var model: RecordingSessionViewModel
    var onReplay: () -> Void
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(model.engine.resultTitle)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                DigitalBoardView(
                    fen: model.engine.fen,
                    orientation: model.orientation,
                    lastMove: model.engine.lastMoveSquares
                )
                .frame(maxHeight: 280)

                FenBar(fen: model.engine.fen, copyAction: model.copyFEN)

                PrimaryButton(title: "Replay", action: onReplay)
                SecondaryButton(title: "Share PGN") {
                    model.sharePGN()
                }
                Button("Done", action: onDone)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)

                if model.canUndo {
                    Button("Undo last move") {
                        model.undoLast()
                    }
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Undo last move")
                }
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showShareSheet) {
            ShareSheet(items: model.shareItems)
        }
    }
}
