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

enum SpeechSettings {
    static let key = "speakCommittedMoves"

    static var speakMoves: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum FastReplySettings {
    static let key = "detectFastReplies"

    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum AutoResumeSettings {
    static let key = "autoResumeAfterReject"
    static let delayMilliseconds: Int = 1000

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum DetectionSettings {
    static let yoloConfidenceKey = "yoloConfidenceThreshold"
    static let classifierConfidenceKey = "classifierConfidenceThreshold"
    static let yoloConfidenceDefault: Double = 0.25
    static let classifierConfidenceDefault: Double = 0.35
    static let yoloConfidenceRange: ClosedRange<Double> = 0.05...0.70
    static let classifierConfidenceRange: ClosedRange<Double> = 0.10...0.80

    static var yoloConfidence: Float { Float(yoloConfidenceValue) }
    static var classifierConfidence: Float { Float(classifierConfidenceValue) }

    static var yoloConfidenceValue: Double {
        get {
            storedDouble(
                for: yoloConfidenceKey,
                default: yoloConfidenceDefault,
                range: yoloConfidenceRange
            )
        }
        set {
            UserDefaults.standard.set(clamp(newValue, to: yoloConfidenceRange), forKey: yoloConfidenceKey)
        }
    }

    static var classifierConfidenceValue: Double {
        get {
            storedDouble(
                for: classifierConfidenceKey,
                default: classifierConfidenceDefault,
                range: classifierConfidenceRange
            )
        }
        set {
            UserDefaults.standard.set(
                clamp(newValue, to: classifierConfidenceRange),
                forKey: classifierConfidenceKey
            )
        }
    }

    static func resetToDefaults() {
        yoloConfidenceValue = yoloConfidenceDefault
        classifierConfidenceValue = classifierConfidenceDefault
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func storedDouble(
        for key: String,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return clamp(UserDefaults.standard.double(forKey: key), to: range)
    }
}

enum DebugOverlaySettings {
    static let showYoloDotsKey = "showYoloDebugDots"
    static let showCaptureDiagnosticsKey = "showCaptureDiagnostics"
    static let showBoardGridKey = "showBoardGrid"
    static let showOccupancyOverlayKey = "showOccupancyOverlay"
    static let showPieceBoxesKey = "showPieceBoxes"

    static var showYoloDots: Bool {
        get { storedBool(for: showYoloDotsKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: showYoloDotsKey) }
    }

    static var showCaptureDiagnostics: Bool {
        get { storedBool(for: showCaptureDiagnosticsKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: showCaptureDiagnosticsKey) }
    }

    static var showBoardGrid: Bool {
        get { storedBool(for: showBoardGridKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: showBoardGridKey) }
    }

    static var showOccupancyOverlay: Bool {
        get { storedBool(for: showOccupancyOverlayKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: showOccupancyOverlayKey) }
    }

    static var showPieceBoxes: Bool {
        get { storedBool(for: showPieceBoxesKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: showPieceBoxesKey) }
    }

    static func resetToDefaults() {
        showYoloDots = true
        showCaptureDiagnostics = true
        showBoardGrid = true
        showOccupancyOverlay = true
        showPieceBoxes = false
    }

    private static func storedBool(for key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
