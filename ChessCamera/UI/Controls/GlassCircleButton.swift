import SwiftUI
import UIKit

/// A non-interactive label view providing the glass circle appearance.
/// Use inside a `Button` or `ToolbarItem` where an outer button wrapper already exists,
/// to avoid the double-button nesting that causes visual stacking artifacts.
struct GlassCircleButtonLabel: View {
    var icon: String?
    var title: String?
    var diameter: CGFloat = 44
    var tintColor: Color? = nil
    var isActive: Bool = false
    var isDestructive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Base material layer
            if reduceTransparency {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: diameter, height: diameter)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: diameter, height: diameter)
            }

            // State tint layer
            Circle()
                .fill(tintLayerColor)
                .frame(width: diameter, height: diameter)

            // Directional specular rim reflection
            Circle()
                .strokeBorder(specularBorderGradient, lineWidth: 1)
                .frame(width: diameter, height: diameter)

            // Icon / Glyph
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(glyphColor)
            } else if let title {
                Text(title)
                    .font(.system(size: diameter * 0.36, weight: .bold))
                    .foregroundStyle(glyphColor)
            }
        }
        // Soft ambient drop shadow & subtle rim light
        .shadow(color: Color.black.opacity(reduceTransparency ? 0.15 : 0.28), radius: 8, x: 0, y: 4)
        .shadow(color: Color.white.opacity(reduceTransparency ? 0.0 : 0.08), radius: 1, x: 0, y: -0.5)
    }

    private var tintLayerColor: Color {
        if isDestructive {
            return Theme.danger.opacity(0.22)
        }
        if isActive {
            return Theme.accent.opacity(0.28)
        }
        if let tintColor {
            return tintColor.opacity(0.18)
        }
        return Color.white.opacity(0.06)
    }

    private var glyphColor: Color {
        if isDestructive {
            return Theme.danger
        }
        if isActive {
            return Theme.accent
        }
        if let tintColor {
            return tintColor
        }
        return Theme.textPrimary
    }

    private var specularBorderGradient: LinearGradient {
        if isDestructive {
            return LinearGradient(
                colors: [
                    Theme.danger.opacity(0.65),
                    Theme.danger.opacity(0.25),
                    Theme.danger.opacity(0.10),
                    Theme.danger.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isActive {
            return LinearGradient(
                colors: [
                    Theme.accent.opacity(0.80),
                    Theme.accent.opacity(0.35),
                    Theme.accent.opacity(0.15),
                    Theme.accent.opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.55), location: 0.0),
                .init(color: Color.white.opacity(0.20), location: 0.35),
                .init(color: Color.white.opacity(0.04), location: 0.70),
                .init(color: Color.white.opacity(0.18), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// A modern circular glass button following Apple's Liquid Glass HIG standards.
/// Uses `.ultraThinMaterial` with directional specular lighting, depth shadow,
/// and responsive spring touch physics.
struct GlassCircleButton: View {
    var icon: String?
    var title: String?
    var diameter: CGFloat = 44
    var tintColor: Color? = nil
    var isActive: Bool = false
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    var action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                // Base material layer (adapts to reduceTransparency accessibility preference)
                if reduceTransparency {
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: diameter, height: diameter)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: diameter, height: diameter)
                }

                // State tint layer (active accent, destructive red, or subtle light reflection)
                Circle()
                    .fill(tintLayerColor)
                    .frame(width: diameter, height: diameter)

                // Directional specular rim reflection (light from top-left)
                Circle()
                    .strokeBorder(specularBorderGradient, lineWidth: 1)
                    .frame(width: diameter, height: diameter)

                // Icon / Glyph
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: diameter * 0.42, weight: .semibold))
                        .foregroundStyle(glyphColor)
                } else if let title {
                    Text(title)
                        .font(.system(size: diameter * 0.36, weight: .bold))
                        .foregroundStyle(glyphColor)
                }
            }
            // Soft ambient drop shadow & subtle rim light
            .shadow(color: Color.black.opacity(reduceTransparency ? 0.15 : 0.28), radius: 8, x: 0, y: 4)
            .shadow(color: Color.white.opacity(reduceTransparency ? 0.0 : 0.08), radius: 1, x: 0, y: -0.5)
            // Pressed spring dynamics (adapts to reduceMotion)
            .scaleEffect((isPressed && !reduceMotion) ? 0.91 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.65), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : (isPressed ? 0.88 : 1.0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isDisabled && !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    if isPressed { isPressed = false }
                }
        )
        .accessibilityLabel(title ?? icon ?? "Button")
    }

    private var tintLayerColor: Color {
        if isDestructive {
            return Theme.danger.opacity(0.22)
        }
        if isActive {
            return Theme.accent.opacity(0.28)
        }
        if let tintColor {
            return tintColor.opacity(0.18)
        }
        // Neutral liquid glass reflection
        return Color.white.opacity(0.06)
    }

    private var glyphColor: Color {
        if isDestructive {
            return Theme.danger
        }
        if isActive {
            return Theme.accent
        }
        if let tintColor {
            return tintColor
        }
        return Theme.textPrimary
    }

    private var specularBorderGradient: LinearGradient {
        if isDestructive {
            return LinearGradient(
                colors: [
                    Theme.danger.opacity(0.65),
                    Theme.danger.opacity(0.25),
                    Theme.danger.opacity(0.10),
                    Theme.danger.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isActive {
            return LinearGradient(
                colors: [
                    Theme.accent.opacity(0.80),
                    Theme.accent.opacity(0.35),
                    Theme.accent.opacity(0.15),
                    Theme.accent.opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.55), location: 0.0),
                .init(color: Color.white.opacity(0.20), location: 0.35),
                .init(color: Color.white.opacity(0.04), location: 0.70),
                .init(color: Color.white.opacity(0.18), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
