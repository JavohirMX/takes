import SwiftUI
import UIKit

enum StatusKind: Equatable {
    case recording(String)
    case disturbed
    case awaitingEdit
    case check(String)
    case trackingLost
    case classifying

    var icon: String {
        switch self {
        case .recording: "record.circle"
        case .disturbed: "hand.raised"
        case .awaitingEdit: "exclamationmark.triangle"
        case .check: "checkmark.circle"
        case .trackingLost: "exclamationmark.triangle"
        case .classifying: "record.circle"
        }
    }

    var color: Color {
        switch self {
        case .recording, .check: Theme.accent
        case .disturbed: Theme.caution
        case .awaitingEdit, .trackingLost: Theme.danger
        case .classifying: Theme.textSecondary
        }
    }

    var copy: String {
        switch self {
        case .recording(let san): san
        case .disturbed: "Waiting for the board…"
        case .awaitingEdit: "Couldn’t read that move"
        case .check(let san): "Check  \(san)"
        case .trackingLost: "Board lost"
        case .classifying: "Reading pieces…"
        }
    }
}

struct StatusBanner: View {
    var kind: StatusKind
    var showFix: Bool = false
    var onFix: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.color)
                .frame(width: 28, height: 28)
            Text(kind.copy)
                .font(.title3.weight(.semibold).monospaced())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
            if showFix {
                Button("Fix", action: { onFix?() })
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.danger, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Fix last move")
            }
            if kind == .trackingLost {
                Image(systemName: "viewfinder")
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(hudBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var hudBackground: Color {
        UIAccessibility.isReduceTransparencyEnabled ? Theme.surface : Theme.surface.opacity(0.95)
    }
}
