import SwiftUI

struct EvalBarView: View {
    var score: EvaluationScore?
    var height: CGFloat = 160

    var body: some View {
        let fraction = score?.whiteBarFraction ?? 0.5
        GeometryReader { proxy in
            let h = proxy.size.height
            let whiteH = h * fraction
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(height: whiteH)
                Text(score?.display ?? "—")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 4)
                    .rotationEffect(.degrees(-90))
                    .frame(width: h, height: proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
        }
        .frame(width: 18, height: height)
        .accessibilityLabel(score.map { "Evaluation \($0.display)" } ?? "No evaluation")
    }
}

#Preview {
    HStack {
        EvalBarView(score: .centipawns(42))
        EvalBarView(score: .mate(3))
        EvalBarView(score: .centipawns(-180))
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
