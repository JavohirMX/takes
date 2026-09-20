import SwiftUI

struct EvalBarView: View {
    var score: EvaluationScore?
    var isFlipped: Bool = false
    var height: CGFloat? = nil

    private var whiteFraction: Double {
        score?.whiteBarFraction ?? 0.5
    }

    /// Fraction of bar from the bottom
    private var bottomFraction: Double {
        let frac = isFlipped ? (1.0 - whiteFraction) : whiteFraction
        return max(0.03, min(0.97, frac))
    }

    private var isWhiteLeading: Bool {
        whiteFraction >= 0.5
    }

    private var scoreText: String {
        guard let score else { return "0.0" }
        switch score {
        case .centipawns(let cp):
            let pawns = Double(abs(cp)) / 100.0
            return String(format: "%.1f", pawns)
        case .mate(let m):
            return "M\(abs(m))"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let totalHeight = height ?? proxy.size.height
            let barWidth = max(24, min(30, proxy.size.width))
            let bottomHeight = totalHeight * CGFloat(bottomFraction)

            ZStack(alignment: .bottom) {
                // Top section (Black when not flipped, White when flipped)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isFlipped ? Color.white : Color(red: 0.13, green: 0.13, blue: 0.14))

                // Bottom section (White when not flipped, Black when flipped)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isFlipped ? Color(red: 0.13, green: 0.13, blue: 0.14) : Color.white)
                    .frame(height: bottomHeight)

                // Integrated score display
                VStack {
                    if !isWhiteLeading {
                        // Black is leading: show score in Black's section
                        let inTop = !isFlipped
                        if inTop {
                            scorePill(textColor: .white, isTop: true)
                            Spacer()
                        } else {
                            Spacer()
                            scorePill(textColor: .white, isTop: false)
                        }
                    } else {
                        // White is leading: show score in White's section
                        let inBottom = !isFlipped
                        if inBottom {
                            Spacer()
                            scorePill(textColor: .black, isTop: false)
                        } else {
                            scorePill(textColor: .black, isTop: true)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bottomFraction)
        }
        .frame(width: 26)
        .frame(height: height)
        .accessibilityLabel(score.map { "Evaluation \($0.display)" } ?? "No evaluation")
    }

    private func scorePill(textColor: Color, isTop: Bool) -> some View {
        Text(scoreText)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
    }
}

#Preview {
    HStack(spacing: 20) {
        EvalBarView(score: .centipawns(140), height: 280)
        EvalBarView(score: .centipawns(-220), height: 280)
        EvalBarView(score: .mate(3), height: 280)
        EvalBarView(score: .centipawns(0), height: 280)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
