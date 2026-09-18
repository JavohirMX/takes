import SwiftUI

struct EvalGraphView: View {
    /// Index 0 = start position; one entry per ply thereafter.
    var series: [EvaluationScore]
    var selectedIndex: Int
    var onSelect: ((Int) -> Void)?

    @State private var isDragging = false
    @State private var dragX: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let count = max(series.count, 2)
            let midY = size.height / 2
            ZStack(alignment: .topLeading) {
                // Midline
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: size.width, y: midY))
                }
                .stroke(Theme.border.opacity(0.6), lineWidth: 1)

                // Area + line
                Path { path in
                    guard series.count > 1 else { return }
                    for (i, score) in series.enumerated() {
                        let x = size.width * CGFloat(i) / CGFloat(count - 1)
                        let y = yPosition(for: score, height: size.height)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Theme.accent, lineWidth: 1.5)

                // Selection line
                if series.indices.contains(selectedIndex) {
                    let x = size.width * CGFloat(selectedIndex) / CGFloat(count - 1)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    .stroke(Theme.textSecondary.opacity(0.7), lineWidth: 1)

                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: yPosition(for: series[selectedIndex], height: size.height))
                }

                // Floating tooltip
                if isDragging, series.indices.contains(selectedIndex) {
                    let score = series[selectedIndex]
                    let moveText = selectedIndex == 0 ? "Start" : "Move \(selectedIndex)"
                    let text = "\(moveText): \(score.display)"
                    let x = size.width * CGFloat(selectedIndex) / CGFloat(count - 1)
                    let clampedX = max(44, min(size.width - 44, x))

                    Text(text)
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.surface, in: Capsule())
                        .overlay {
                            Capsule().stroke(Theme.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .position(x: clampedX, y: 14)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard series.count > 1, let onSelect else { return }
                        isDragging = true
                        dragX = value.location.x
                        let fraction = max(0, min(1, value.location.x / max(size.width, 1)))
                        let index = Int((fraction * CGFloat(series.count - 1)).rounded())
                        if index != selectedIndex {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        onSelect(index)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: 72)
        .padding(.horizontal, 4)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Evaluation graph")
    }

    private func yPosition(for score: EvaluationScore, height: CGFloat) -> CGFloat {
        // Map ±8 pawns to the view; White up.
        let pawns = Double(score.approximateCentipawns) / 100.0
        let clamped = max(-8, min(8, pawns))
        let fraction = (clamped + 8) / 16 // 0…1 White-up from bottom conceptually
        return height * (1 - CGFloat(fraction))
    }
}

#Preview {
    EvalGraphView(
        series: [
            .centipawns(0),
            .centipawns(20),
            .centipawns(-40),
            .centipawns(120),
            .centipawns(80),
            .mate(2)
        ],
        selectedIndex: 2
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
