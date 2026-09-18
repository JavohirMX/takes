import SwiftUI

struct GameOverView: View {
    @Bindable var model: RecordingSessionViewModel
    var onReplay: () -> Void
    var onDone: () -> Void

    @State private var showEditDetails = false

    private var displayTitle: String {
        if let result = model.savedRecord?.resultOverride ?? model.pendingResultOverride {
            switch result {
            case "1-0": return "White Wins"
            case "0-1": return "Black Wins"
            case "½-½", "1/2-1/2": return "Draw"
            default: return model.engine.resultTitle
            }
        }
        return model.engine.resultTitle
    }

    private var openingName: String? {
        model.savedRecord?.openingName ?? OpeningDetector.detect(sans: model.committedSANs)
    }

    private var playersSummary: String? {
        let white = model.savedRecord?.whitePlayer ?? model.pendingWhitePlayer
        let black = model.savedRecord?.blackPlayer ?? model.pendingBlackPlayer
        if let white, let black, !white.isEmpty, !black.isEmpty {
            return "\(white) vs \(black)"
        } else if let white, !white.isEmpty {
            return "White: \(white)"
        } else if let black, !black.isEmpty {
            return "Black: \(black)"
        }
        return nil
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text(displayTitle)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        if let players = playersSummary {
                            Text(players)
                                .font(.headline)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        if let opening = openingName {
                            HStack(spacing: 4) {
                                Image(systemName: "book.closed.fill")
                                Text(opening)
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                    }

                    DigitalBoardView(
                        fen: model.engine.fen,
                        lastMove: model.engine.lastMoveSquares
                    )
                    .frame(maxHeight: 280)

                    FenBar(fen: model.engine.fen, copyAction: model.copyFEN)

                    VStack(spacing: 12) {
                        PrimaryButton(title: "Replay", action: onReplay)

                        HStack(spacing: 12) {
                            SecondaryButton(title: "Share PGN") {
                                model.sharePGN()
                            }

                            Button {
                                _ = model.savedRecordIfNeeded()
                                showEditDetails = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                    Text("Edit Info")
                                }
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Theme.textPrimary)
                                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Theme.border, lineWidth: 1)
                                }
                            }
                        }

                        Button("Done", action: onDone)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minHeight: 44)

                        if model.canUndo {
                            Button("Undo last move") {
                                model.undoLast()
                            }
                            .font(.callout)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Undo last move")
                        }
                    }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEditDetails) {
            if let record = model.savedRecordIfNeeded() {
                EditGameDetailsSheet(game: record)
            }
        }
        .sheet(isPresented: $model.showShareSheet) {
            ShareSheet(items: model.shareItems)
        }
    }
}

