import SwiftUI

struct BoardAppearanceSheet: View {
    @AppStorage(BoardAppearance.styleKey) private var styleRaw = BoardAppearance.defaultStyle.rawValue
    @Environment(\.dismiss) private var dismiss

    private var selected: BoardStyle {
        BoardStyle(rawValue: styleRaw) ?? BoardAppearance.defaultStyle
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Applies to live, replay, confirm, and history.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(BoardStyle.allCases) { style in
                        Button {
                            styleRaw = style.rawValue
                        } label: {
                            VStack(spacing: 8) {
                                DigitalBoardView(
                                    fen: FenCodec.standard,
                                    showsCoordinates: false,
                                    styleOverride: style
                                )
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            selected == style ? Theme.accent : Theme.border,
                                            lineWidth: selected == style ? 3 : 1
                                        )
                                }
                                HStack(spacing: 6) {
                                    Text(style.title)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    if selected == style {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(style.title)
                        .accessibilityAddTraits(selected == style ? .isSelected : [])
                    }
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Board appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    BoardAppearanceSheet()
}
