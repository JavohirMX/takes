import SwiftUI

struct SecondaryButton: View {
    let title: String
    var isDisabled: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(isDisabled ? Theme.textSecondary : Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: 16) {
        SecondaryButton(title: "Adjust corners")
        SecondaryButton(title: "Disabled", isDisabled: true)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
