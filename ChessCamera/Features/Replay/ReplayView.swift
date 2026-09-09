import SwiftUI
import UIKit

struct ReplayView: View {
    let pgn: String
    let title: String
    var initialFen: String? = nil

    @State private var plyIndex = 0
    @State private var sans: [String] = []
    @State private var fens: [String] = []
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                DigitalBoardView(
                    fen: currentFEN,
                    lastMove: lastMoveHighlight
                )
                .padding(.horizontal, 16)

                HStack(spacing: 16) {
                    Button {
                        plyIndex = max(plyIndex - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(plyIndex == 0)
                    .accessibilityLabel("Previous move")

                    Text(plyCaption)
                        .font(.body.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)

                    Button {
                        plyIndex = min(plyIndex + 1, sans.count)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(plyIndex >= sans.count)
                    .accessibilityLabel("Next move")
                }
                .padding(.horizontal, 16)

                MoveListView(sans: sans, selectedPly: plyIndex == 0 ? nil : plyIndex - 1) { index in
                    plyIndex = index + 1
                }

                FenBar(fen: currentFEN) {
                    UIPasteboard.general.string = currentFEN
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share PGN") { sharePGN() }
                    Button("Copy PGN") { UIPasteboard.general.string = pgn }
                    Button("Copy FEN") { UIPasteboard.general.string = currentFEN }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share")
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .onAppear { rebuild() }
    }

    private var currentFEN: String {
        guard plyIndex >= 0, plyIndex < fens.count else {
            return initialFen ?? FenCodec.standard
        }
        return fens[plyIndex]
    }

    private var lastMoveHighlight: (from: ChessSquare, to: ChessSquare)? {
        guard plyIndex > 0, plyIndex <= sans.count else { return nil }
        do {
            let engine = GameEngine()
            for san in sans.prefix(plyIndex) {
                try engine.apply(san: san)
            }
            return engine.lastMoveSquares
        } catch {
            return nil
        }
    }

    private var plyCaption: String {
        if plyIndex == 0 { return "Start" }
        return "\(plyIndex)/\(sans.count)  \(sans[plyIndex - 1])"
    }

    private func rebuild() {
        sans = PGNMoveList.sans(from: pgn)
        var frames = [FenCodec.standard]
        let engine = GameEngine()
        for san in sans {
            do {
                try engine.apply(san: san)
                frames.append(engine.fen)
            } catch {
                break
            }
        }
        fens = frames
        plyIndex = 0
    }

    private func sharePGN() {
        do {
            shareItems = [try PGNShareFile.write(pgn: pgn, title: title)]
            showShare = true
        } catch {
            UIPasteboard.general.string = pgn
        }
    }
}

#Preview {
    NavigationStack {
        ReplayView(pgn: "1. e4 e5 2. Nf3", title: "Game · Sep 9")
    }
}
