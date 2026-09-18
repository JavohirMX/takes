import SwiftUI
import UIKit

/// Floating circular magnification loupe (2x zoom) that displays the board area under
/// the corner handle, offset above the finger so the user's thumb never obscures the corner.
struct MagnificationLoupeView: View {
    var image: CGImage?
    var point: CGPoint
    var viewSize: CGSize
    var label: String
    var loupeSize: CGFloat = 84
    var zoomScale: CGFloat = 2.2

    var body: some View {
        ZStack {
            // Loupe background & zoomed content
            ZStack {
                Theme.surfaceMuted
                if let image, viewSize.width > 0, viewSize.height > 0 {
                    // Position image so that `point` is centered in the loupe
                    Image(uiImage: UIImage(cgImage: image))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: viewSize.width * zoomScale, height: viewSize.height * zoomScale)
                        .position(
                            x: (loupeSize / 2) + (viewSize.width / 2 - point.x) * zoomScale,
                            y: (loupeSize / 2) + (viewSize.height / 2 - point.y) * zoomScale
                        )
                }

                // Crosshairs
                Path { path in
                    // Horizontal
                    path.move(to: CGPoint(x: 0, y: loupeSize / 2))
                    path.addLine(to: CGPoint(x: loupeSize, y: loupeSize / 2))
                    // Vertical
                    path.move(to: CGPoint(x: loupeSize / 2, y: 0))
                    path.addLine(to: CGPoint(x: loupeSize / 2, y: loupeSize))
                }
                .stroke(Theme.accent, lineWidth: 1.2)

                // Center target dot
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 4, height: 4)
            }
            .frame(width: loupeSize, height: loupeSize)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 2.5)
            }
            .shadow(color: .black.opacity(0.65), radius: 6, x: 0, y: 3)

            // Corner label badge
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.accent, in: Capsule())
                .offset(y: -(loupeSize / 2 + 10))
        }
    }
}
