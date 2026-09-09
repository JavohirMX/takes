import SwiftUI

struct PrimaryButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal, 16)
        }
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(title)
    }
}

#Preview {
    PrimaryButton(title: "New Game")
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
