import SwiftUI

/// Vector isometric illustration showing an iPhone propped beside a chessboard.
struct SetupPrimerDiagram: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.border.opacity(0.5), lineWidth: 1)
                }

            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    // Isometric Chessboard icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surfaceMuted)
                            .frame(width: 84, height: 84)
                            .rotation3DEffect(.degrees(45), axis: (x: 1, y: 0, z: 0))

                        Image(systemName: "checkerboard.rectangle")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    // Scan beam arrow
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                        Text("35°–45°")
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    // iPhone propped on stand
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 2)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                            .frame(width: 44, height: 80)
                            .rotationEffect(.degrees(-15))

                        // Camera lens
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: -8, y: -26)
                    }
                }
                .padding(.top, 10)

                Text("Prop iPhone at side or flank of board")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
        }
        .frame(height: 140)
    }
}
