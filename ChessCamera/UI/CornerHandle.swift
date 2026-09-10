import SwiftUI

struct CornerHandle: View {
    var label: String
    var point: CGPoint
    var onDrag: (CGPoint) -> Void
    var onEnded: () -> Void = {}
    @State private var dragOrigin: CGPoint?

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 18, height: 18)
            .overlay {
                Circle().stroke(Theme.onAccent.opacity(0.8), lineWidth: 1)
            }
            .overlay {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .offset(y: -24)
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = point }
                        if let dragOrigin {
                            onDrag(
                                CGPoint(
                                    x: dragOrigin.x + value.translation.width,
                                    y: dragOrigin.y + value.translation.height
                                )
                            )
                        }
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        onEnded()
                    }
            )
            .accessibilityLabel("Corner \(label)")
    }
}
