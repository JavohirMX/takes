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
