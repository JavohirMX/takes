import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appending(path: "import-\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ImportedMovie(url: dest)
        }
    }
}

enum SetupFlags {
    static let primerKey = "didSeeSetupPrimer"

    static var didSeePrimer: Bool {
        get { UserDefaults.standard.bool(forKey: primerKey) }
        set { UserDefaults.standard.set(newValue, forKey: primerKey) }
    }
}

enum SettleSettings {
    static let key = "settleMilliseconds"

    static var milliseconds: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: key)
            return value == 0 ? 600 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
