import SwiftUI

/// Expandable score sheet drawer for portrait live recording, allowing players
/// to review all previous moves, check repetitions, and view the detected opening.
struct MoveSheetDrawer: View {
    let sans: [String]
    let fen: String
    var moveTimes: [TimeInterval]? = nil
    var onDismiss: () -> Void
    var onEditPly: ((Int) -> Void)? = nil

    private var openingName: String? {
        OpeningDetector.detect(sans: sans)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let openingName {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(Theme.accent)
                        Text(openingName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                MoveListView(sans: sans, moveTimes: moveTimes, onEditPly: onEditPly)
                    .padding(.horizontal, 16)

                Divider()
                    .background(Theme.border.opacity(0.5))

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = PGNMoveList.preview(sans: sans, maxPlies: sans.count)
                    } label: {
                        Label("Copy PGN", systemImage: "doc.on.doc")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        UIPasteboard.general.string = fen
                    } label: {
                        Label("Copy FEN", systemImage: "square.on.square")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Score Sheet (\(sans.count) moves)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
