import SwiftUI

struct CornerHandle: View {
    var label: String
    var point: CGPoint
    var image: CGImage? = nil
    var viewSize: CGSize = .zero
    var onDrag: (CGPoint) -> Void
    var onEnded: () -> Void = {}
    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var lastHapticPoint: CGPoint = .zero

    var body: some View {
        ZStack {
            // Handle circle
            Circle()
                .fill(Theme.accent)
                .frame(width: isDragging ? 22 : 18, height: isDragging ? 22 : 18)
                .overlay {
                    Circle().stroke(Theme.onAccent.opacity(0.8), lineWidth: 1.5)
                }
                .overlay {
                    if !isDragging {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize()
                            .offset(y: -24)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .position(point)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            if dragOrigin == nil {
                                dragOrigin = point
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                            if let dragOrigin {
                                let target = CGPoint(
                                    x: dragOrigin.x + value.translation.width,
                                    y: dragOrigin.y + value.translation.height
                                )
                                onDrag(target)
                                if hypot(target.x - lastHapticPoint.x, target.y - lastHapticPoint.y) > 16 {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    lastHapticPoint = target
                                }
                            }
                        }
                        .onEnded { _ in
                            dragOrigin = nil
                            isDragging = false
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onEnded()
                        }
                )
                .accessibilityLabel("Corner \(label)")

            // Floating 2x magnification loupe offset above finger
            if isDragging {
                MagnificationLoupeView(
                    image: image,
                    point: point,
                    viewSize: viewSize,
                    label: label
                )
                .position(x: point.x, y: max(55, point.y - 68))
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }
}
