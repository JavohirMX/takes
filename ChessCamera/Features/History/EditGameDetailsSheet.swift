import SwiftUI

struct EditGameDetailsSheet: View {
    @Bindable var game: GameRecord
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var whitePlayer: String = ""
    @State private var blackPlayer: String = ""
    @State private var event: String = ""
    @State private var result: String = "*"
    @State private var initialFen: String = ""

    private let resultOptions = ["*", "1-0", "0-1", "½-½"]

    private var isFenValid: Bool {
        let trimmed = initialFen.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || FenCodec.isStandardStart(trimmed) { return true }
        return FenCodec.isLegal(trimmed)
    }

    private var isMidGameMatch: Bool {
        let fen = game.initialFen ?? PGNMoveList.extractFEN(from: game.pgn)
        guard let fen else { return false }
        return !FenCodec.isStandardStart(fen)
    }

    init(game: GameRecord) {
        self.game = game
        _title = State(initialValue: game.title)
        _whitePlayer = State(initialValue: game.whitePlayer ?? "")
        _blackPlayer = State(initialValue: game.blackPlayer ?? "")
        _event = State(initialValue: game.event ?? "")
        _result = State(initialValue: game.displayResult)
        _initialFen = State(initialValue: game.initialFen ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Match Title") {
                    TextField("Title", text: $title)
                        .foregroundStyle(Theme.textPrimary)
                }

                Section("Players") {
                    TextField("White", text: $whitePlayer)
                        .foregroundStyle(Theme.textPrimary)
                    TextField("Black", text: $blackPlayer)
                        .foregroundStyle(Theme.textPrimary)
                }

                Section("Event") {
                    TextField("Event or Venue", text: $event)
                        .foregroundStyle(Theme.textPrimary)
                }

                Section("Result") {
                    Picker("Result", selection: $result) {
                        ForEach(resultOptions, id: \.self) { token in
                            Text(token).tag(token)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if isMidGameMatch {
                    Section {
                        TextField("Standard starting position", text: $initialFen, axis: .vertical)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2...4)
                    } header: {
                        Text("Starting Position (FEN)")
                    } footer: {
                        if !isFenValid {
                            Text("Invalid FEN notation. Please enter a valid chess board position.")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        } else {
                            Text("Specify starting FEN if the game began from an arbitrary position. Leave blank for standard chess starting position.")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFenValid ? Theme.accent : Theme.textSecondary)
                    .disabled(!isFenValid)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        if !trimmedTitle.isEmpty {
            game.title = trimmedTitle
        }
        game.whitePlayer = whitePlayer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : whitePlayer.trimmingCharacters(in: .whitespaces)
        game.blackPlayer = blackPlayer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : blackPlayer.trimmingCharacters(in: .whitespaces)
        game.event = event.trimmingCharacters(in: .whitespaces).isEmpty ? nil : event.trimmingCharacters(in: .whitespaces)
        game.resultOverride = result == "*" ? nil : result

        if isMidGameMatch {
            let trimmedFen = initialFen.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedFen: String? = (trimmedFen.isEmpty || FenCodec.isStandardStart(trimmedFen)) ? nil : trimmedFen
            if game.initialFen != resolvedFen {
                game.initialFen = resolvedFen
                game.clearPersistedAnalysis()
            }
        }
    }
}
