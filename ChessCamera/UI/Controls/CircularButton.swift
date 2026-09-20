import SwiftUI
import UIKit

enum CircularButtonStyle {
    case primary
    case secondary
    case destructive
    case glass
    case plain
}

struct CircularButton: View {
    var icon: String?
    var text: String?
    var style: CircularButtonStyle
    var diameter: CGFloat
    var isDisabled: Bool
    var action: (() -> Void)?

    init(
        icon: String? = nil,
        title: String? = nil,
        text: String? = nil,
        style: CircularButtonStyle = .secondary,
        role: CircularButtonStyle? = nil,
        diameter: CGFloat = 44,
        size: CGFloat? = nil,
        isDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.text = text ?? title
        self.style = role ?? style
        self.diameter = size ?? diameter
        self.isDisabled = isDisabled
        self.action = action
    }

    @State private var isPressed = false

    var body: some View {
        if let action {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isDisabled && !isPressed { isPressed = true }
                    }
                    .onEnded { _ in
                        if isPressed { isPressed = false }
                    }
            )
        } else {
            content
                .opacity(isDisabled ? 0.45 : 1.0)
        }
    }

    private var content: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: diameter, height: diameter)

            if hasBorder {
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1)
                    .frame(width: diameter, height: diameter)
            }

            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: diameter * 0.42, weight: .semibold))
                } else if let text {
                    Text(text)
                        .font(.system(size: diameter * 0.36, weight: .bold))
                }
            }
            .foregroundStyle(foregroundColor)
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isPressed)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return Theme.accent
        case .secondary:
            return Theme.surface
        case .destructive:
            return Theme.danger.opacity(0.18)
        case .glass:
            return Theme.surface.opacity(0.85)
        case .plain:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return Theme.onAccent
        case .secondary, .glass:
            return Theme.textPrimary
        case .destructive:
            return Theme.danger
        case .plain:
            return Theme.textPrimary
        }
    }

    private var hasBorder: Bool {
        switch style {
        case .secondary, .glass:
            return true
        case .destructive:
            return true
        default:
            return false
        }
    }

    private var borderColor: Color {
        switch style {
        case .destructive:
            return Theme.danger.opacity(0.4)
        default:
            return Theme.border
        }
    }
}
