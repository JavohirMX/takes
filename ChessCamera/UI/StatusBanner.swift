import SwiftUI
import UIKit

enum StatusKind: Equatable {
    case recording(String)
    case disturbed(holding: String?)
    case awaitingEdit
    case softReject(String)
    case check(String)
    case trackingLost
    case classifying

    var icon: String {
        switch self {
        case .recording: "record.circle"
        case .disturbed: "hand.raised"
        case .awaitingEdit, .softReject: "exclamationmark.triangle"
        case .check: "checkmark.circle"
        case .trackingLost: "exclamationmark.triangle"
        case .classifying: "record.circle"
        }
    }

    var color: Color {
        switch self {
        case .recording, .check: Theme.accent
        case .disturbed: Theme.caution
        case .awaitingEdit, .trackingLost, .softReject: Theme.danger
        case .classifying: Theme.textSecondary
        }
    }

    var copy: String {
        switch self {
        case .recording(let san):
            san
        case .disturbed(let san):
            if let san, !san.isEmpty {
                "\(san)  … waiting"
            } else {
                "Waiting for the board…"
            }
        case .awaitingEdit:
            "Couldn’t read that move"
        case .softReject(let message):
            message
        case .check(let san):
            "Check  \(san)"
        case .trackingLost:
            "Board lost"
        case .classifying:
            "Reading pieces…"
        }
    }
}

struct StatusBanner: View {
    var kind: StatusKind
    var showFix: Bool = false
    var onFix: (() -> Void)?
    var showResume: Bool = false
    var onResume: (() -> Void)?

    @State private var settleProgress: CGFloat = 0.0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if case .disturbed = kind {
                    Circle()
                        .stroke(Theme.caution.opacity(0.25), lineWidth: 2.5)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: settleProgress)
                        .stroke(Theme.caution, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 32, height: 32)
                }
                Image(systemName: kind.icon)
                    .foregroundStyle(kind.color)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 32, height: 32)
            .onAppear { updateSettleAnimation() }
            .onChange(of: kind) { _, _ in updateSettleAnimation() }

            Text(kind.copy)
                .font(.title3.weight(.semibold).monospaced())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
            if showResume {
                Button("Resume", action: { onResume?() })
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Resume recording")
            }
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

    private func updateSettleAnimation() {
        if case .disturbed = kind {
            settleProgress = 0.0
            let duration = Double(SettleSettings.milliseconds) / 1000.0
            withAnimation(.linear(duration: duration)) {
                settleProgress = 1.0
            }
        } else {
            settleProgress = 0.0
        }
    }
}
