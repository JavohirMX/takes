import SwiftUI

struct BoardAppearanceSheet: View {
    @AppStorage(BoardAppearance.styleKey) private var styleRaw = BoardAppearance.defaultStyle.rawValue
    @AppStorage(ArrowAppearance.colorKey) private var arrowColorRaw = ArrowAppearance.defaultColor.rawValue
    @AppStorage(MoveAnimationAppearance.key) private var moveAnimationRaw = MoveAnimationAppearance.defaultStyle.rawValue
    @Environment(\.dismiss) private var dismiss

    private var selected: BoardStyle {
        BoardStyle(rawValue: styleRaw) ?? BoardAppearance.defaultStyle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                                        styleOverride: style,
                                        animateMove: false
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

                    Divider()
                        .overlay(Theme.border)
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Best Move Arrow Color")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        Text("Choose the accent color used for engine recommendation arrows.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 12) {
                            ForEach(BestMoveArrowColor.allCases) { option in
                                Button {
                                    arrowColorRaw = option.rawValue
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(option.color)
                                            .frame(width: 36, height: 36)
                                            .overlay {
                                                if arrowColorRaw == option.rawValue {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundStyle(.white)
                                                        .shadow(color: .black.opacity(0.4), radius: 2)
                                                }
                                            }
                                            .overlay {
                                                Circle()
                                                    .strokeBorder(
                                                        arrowColorRaw == option.rawValue ? Color.white : Theme.border,
                                                        lineWidth: arrowColorRaw == option.rawValue ? 2.5 : 1
                                                    )
                                            }

                                        Text(option.title)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(
                                                arrowColorRaw == option.rawValue
                                                    ? Theme.textPrimary
                                                    : Theme.textSecondary
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                            }
                        }
                        .padding(.top, 4)
                    }

                    Divider()
                        .overlay(Theme.border)
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Move Animation")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        Text("Choose how pieces animate when moves are played or replayed.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        VStack(spacing: 8) {
                            ForEach(MoveAnimationStyle.allCases) { option in
                                Button {
                                    moveAnimationRaw = option.rawValue
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: option.icon)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(moveAnimationRaw == option.rawValue ? Theme.accent : Theme.textSecondary)
                                            .frame(width: 28, height: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(Theme.textPrimary)
                                            Text(option.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textSecondary)
                                        }

                                        Spacer()

                                        if moveAnimationRaw == option.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                moveAnimationRaw == option.rawValue ? Theme.accent.opacity(0.8) : Theme.border,
                                                lineWidth: moveAnimationRaw == option.rawValue ? 1.5 : 1
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
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
