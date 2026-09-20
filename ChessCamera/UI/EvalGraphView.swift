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
                // Background fills for White (top) and Black (bottom) advantages
                if series.count > 1 {
                    let fillPath = polygonPath(size: size, count: count, midY: midY)

                    // White advantage area (above midline)
                    fillPath
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.40),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .clipShape(
                            Rectangle()
                                .path(in: CGRect(x: 0, y: 0, width: size.width, height: midY))
                        )

                    // Black advantage area (below midline)
                    fillPath
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.30),
                                    Color.black.opacity(0.75)
                                ],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(
                            Rectangle()
                                .path(in: CGRect(x: 0, y: midY, width: size.width, height: midY))
                        )
                }

                // Center 0.0 midline
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: size.width, y: midY))
                }
                .stroke(
                    Theme.border.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                // The evaluation line itself
                if series.count > 1 {
                    curvePath(size: size, count: count)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white, Theme.accent, Color.gray],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                }

                // Selection cursor
                if series.indices.contains(selectedIndex) {
                    let x = size.width * CGFloat(selectedIndex) / CGFloat(count - 1)
                    let y = yPosition(for: series[selectedIndex], height: size.height)

                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    .stroke(Theme.accent.opacity(0.85), lineWidth: 1.5)

                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle().stroke(Color.white, lineWidth: 1.5)
                        }
                        .position(x: x, y: y)
                }

                // Dragging / Active Tooltip
                if isDragging, series.indices.contains(selectedIndex) {
                    let score = series[selectedIndex]
                    let moveText = selectedIndex == 0 ? "Start" : "Move \(selectedIndex)"
                    let text = "\(moveText) · \(score.display)"
                    let x = size.width * CGFloat(selectedIndex) / CGFloat(count - 1)
                    let clampedX = max(52, min(size.width - 52, x))

                    Text(text)
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.surface, in: Capsule())
                        .overlay {
                            Capsule().stroke(Theme.accent.opacity(0.8), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
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
                        withAnimation(.easeOut(duration: 0.25)) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: 76)
        .padding(.horizontal, 4)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border.opacity(0.6), lineWidth: 1)
        }
        .accessibilityLabel("Evaluation graph")
    }

    private func curvePath(size: CGSize, count: Int) -> Path {
        Path { path in
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
    }

    private func polygonPath(size: CGSize, count: Int, midY: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: midY))
            for (i, score) in series.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(count - 1)
                let y = yPosition(for: score, height: size.height)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: midY))
            path.closeSubpath()
        }
    }

    private func yPosition(for score: EvaluationScore, height: CGFloat) -> CGFloat {
        // Map ±8 pawns to the view; White up (y = 0), Black down (y = height).
        let pawns = Double(score.approximateCentipawns) / 100.0
        let clamped = max(-7.5, min(7.5, pawns))
        let fraction = (clamped + 7.5) / 15.0 // 0…1 White-up from bottom conceptually
        return height * (1 - CGFloat(fraction))
    }
}
