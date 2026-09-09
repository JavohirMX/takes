import SwiftUI

struct MoveListView: View {
    var sans: [String]
    var selectedPly: Int?
    var onSelect: ((Int) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if sans.isEmpty {
                        Text("No moves yet")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(Array(stride(from: 0, to: sans.count, by: 2)), id: \.self) { start in
                        let number = start / 2 + 1
                        HStack(spacing: 8) {
                            Text("\(number).")
                                .font(.body.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(minWidth: 28, alignment: .trailing)
                            plyButton(index: start)
                            if start + 1 < sans.count {
                                plyButton(index: start + 1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: selectedPly) { _, ply in
                if let ply {
                    proxy.scrollTo(ply, anchor: .center)
                }
            }
        }
    }

    private func plyButton(index: Int) -> some View {
        let san = sans[index]
        let selected = selectedPly == index
        return Button {
            onSelect?(index)
        } label: {
            Text(san)
                .font(.body.monospaced())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    selected ? Theme.accent.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .frame(minHeight: 44)
        }
        .id(index)
        .disabled(onSelect == nil)
        .accessibilityLabel(spokenMove(index: index, san: san))
    }

    private func spokenMove(index: Int, san: String) -> String {
        let number = index / 2 + 1
        return "Move \(number), \(SANSpeech.speak(san))"
    }
}

enum SANSpeech {
    static func speak(_ san: String) -> String {
        san
            .replacingOccurrences(of: "K", with: "king ")
            .replacingOccurrences(of: "Q", with: "queen ")
            .replacingOccurrences(of: "R", with: "rook ")
            .replacingOccurrences(of: "B", with: "bishop ")
            .replacingOccurrences(of: "N", with: "knight ")
            .replacingOccurrences(of: "x", with: " takes ")
            .replacingOccurrences(of: "O-O-O", with: "long castle")
            .replacingOccurrences(of: "O-O", with: "short castle")
            .replacingOccurrences(of: "+", with: " check")
            .replacingOccurrences(of: "#", with: " mate")
            .replacingOccurrences(of: "=", with: " promotes to ")
    }
}
