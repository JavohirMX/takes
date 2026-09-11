import SwiftUI

struct PieceBoxOverlay: View {
    var boxes: [PieceDetection.Box]
    var bufferSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            ForEach(boxes) { box in
                let rect = VideoMapping.bufferToView(
                    rect: box.bufferRect,
                    viewSize: proxy.size,
                    bufferSize: bufferSize
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(box.overlayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .frame(width: max(rect.width, 1), height: max(rect.height, 1), alignment: .topLeading)
                .overlay {
                    Rectangle()
                        .stroke(Theme.accent, lineWidth: 2)
                }
                .position(x: rect.midX, y: rect.midY)
                .accessibilityLabel(box.overlayLabel)
            }
        }
        .allowsHitTesting(false)
    }
}
