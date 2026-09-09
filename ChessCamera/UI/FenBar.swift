import SwiftUI
import UIKit

struct FenBar: View {
    var fen: String
    var copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FEN")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .top, spacing: 8) {
                Text(fen)
                    .font(.body.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Copy FEN")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
