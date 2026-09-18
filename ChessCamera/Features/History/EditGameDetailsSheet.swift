import SwiftUI

struct EditGameDetailsSheet: View {
    @Bindable var game: GameRecord
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var whitePlayer: String = ""
    @State private var blackPlayer: String = ""
    @State private var event: String = ""
    @State private var result: String = "*"

    private let resultOptions = ["*", "1-0", "0-1", "½-½"]

    init(game: GameRecord) {
        self.game = game
        _title = State(initialValue: game.title)
        _whitePlayer = State(initialValue: game.whitePlayer ?? "")
        _blackPlayer = State(initialValue: game.blackPlayer ?? "")
        _event = State(initialValue: game.event ?? "")
        _result = State(initialValue: game.displayResult)
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
                    .foregroundStyle(Theme.accent)
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
    }
}
