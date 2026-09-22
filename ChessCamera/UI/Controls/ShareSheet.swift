import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum CropExporter {
    static func export(warped: CGImage, orientation: BoardOrientation) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "chess-crops-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let crops = GridSampler.crops(from: warped, orientation: orientation, inset: 0)
        for crop in crops {
            let url = folder.appending(path: "\(crop.square.algebraic).png")
            guard let data = UIImage(cgImage: crop.image).pngData() else { continue }
            try data.write(to: url)
        }
        let readme = """
        64 square crops from a warped chessboard.
        Filename is the algebraic square (a1–h8).
        Label 13 classes: empty + 12 piece types, then train PieceClassifier.mlmodel in Create ML.
        """
        try readme.write(to: folder.appending(path: "README.txt"), atomically: true, encoding: .utf8)
        return folder
    }
}

enum PGNShareFile {
    static func write(pgn: String, title: String = "game") throws -> URL {
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safe).pgn")
        try pgn.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@MainActor
enum PlatformAnalysisExporter {
    static func chessComURL(pgn: String) -> URL {
        var components = URLComponents(string: "https://www.chess.com/analysis")
        components?.queryItems = [URLQueryItem(name: "pgn", value: pgn)]
        return components?.url ?? URL(string: "https://www.chess.com/analysis")!
    }

    static func fetchLichessURL(pgn: String) async -> URL {
        guard let requestUrl = URL(string: "https://lichess.org/api/import") else {
            return URL(string: "https://lichess.org/paste")!
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "pgn", value: pgn)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let urlString = json["url"] as? String,
               let gameUrl = URL(string: urlString) {
                return gameUrl
            }
        } catch {
            // Network or decoding error; fallback to paste
        }

        return URL(string: "https://lichess.org/paste")!
    }

    static func exportToLichess(pgn: String) {
        UIPasteboard.general.string = pgn
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            let url = await fetchLichessURL(pgn: pgn)
            await UIApplication.shared.open(url)
        }
    }

    static func copyLichessLink(pgn: String, onCopied: ((String) -> Void)? = nil) {
        UIPasteboard.general.string = pgn
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            let url = await fetchLichessURL(pgn: pgn)
            UIPasteboard.general.string = url.absoluteString
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCopied?("Lichess analysis link copied")
        }
    }

    static func exportToChessCom(pgn: String) {
        UIPasteboard.general.string = pgn
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let url = chessComURL(pgn: pgn)
        UIApplication.shared.open(url)
    }

    static func copyChessComLink(pgn: String, onCopied: ((String) -> Void)? = nil) {
        let url = chessComURL(pgn: pgn)
        UIPasteboard.general.string = url.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCopied?("Chess.com analysis link copied")
    }
}

struct ExternalAnalysisMenu: View {
    let pgn: String
    var onCopied: ((String) -> Void)? = nil

    var body: some View {
        Menu {
            Section("Lichess") {
                Button {
                    PlatformAnalysisExporter.exportToLichess(pgn: pgn)
                } label: {
                    Label("Analyze on Lichess", systemImage: "arrow.up.right.square")
                }

                Button {
                    PlatformAnalysisExporter.copyLichessLink(pgn: pgn, onCopied: onCopied)
                } label: {
                    Label("Copy Lichess Link", systemImage: "doc.on.doc")
                }
            }

            Section("Chess.com") {
                Button {
                    PlatformAnalysisExporter.exportToChessCom(pgn: pgn)
                } label: {
                    Label("Analyze on Chess.com", systemImage: "arrow.up.right.square")
                }

                Button {
                    PlatformAnalysisExporter.copyChessComLink(pgn: pgn, onCopied: onCopied)
                } label: {
                    Label("Copy Chess.com Link", systemImage: "doc.on.doc")
                }
            }
        } label: {
            Label("Analyze Externally", systemImage: "arrow.up.right.square")
        }
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Theme.surface)
                            .overlay(Capsule().stroke(Theme.border.opacity(0.8), lineWidth: 1))
                            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
                    )
                    .padding(.bottom, 24)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(999)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
            .onChange(of: message) { _, newValue in
                guard newValue != nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    if message == newValue {
                        withAnimation {
                            message = nil
                        }
                    }
                }
            }
    }
}

extension View {
    func actionToast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
