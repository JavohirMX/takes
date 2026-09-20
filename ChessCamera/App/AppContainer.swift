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

enum SoundSettings {
    static let key = "playMoveSounds"

    static var playSounds: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum MatchModeSettings {
    static let key = "matchModeAutoDim"

    static var autoDim: Bool {
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

enum BoardCalibrationSettings {
    static let key = "rememberBoardSetup"

    static var rememberSetup: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum ClockPreset: String, CaseIterable, Identifiable, Sendable {
    case off
    case fivePlusThree = "5+3"
    case tenPlusFive = "10+5"
    case fifteenPlusTen = "15+10"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .fivePlusThree: "5+3"
        case .tenPlusFive: "10+5"
        case .fifteenPlusTen: "15+10"
        case .custom: "Custom"
        }
    }

    /// Base seconds for fixed presets. `nil` for Off / Custom.
    var fixedBaseSeconds: TimeInterval? {
        switch self {
        case .off, .custom: nil
        case .fivePlusThree: 5 * 60
        case .tenPlusFive: 10 * 60
        case .fifteenPlusTen: 15 * 60
        }
    }

    /// Increment seconds for fixed presets. `nil` for Off / Custom.
    var fixedIncrementSeconds: TimeInterval? {
        switch self {
        case .off, .custom: nil
        case .fivePlusThree: 3
        case .tenPlusFive: 5
        case .fifteenPlusTen: 10
        }
    }
}

enum GameClockSettings {
    static let presetKey = "gameClockPreset"
    static let customBaseMinutesKey = "gameClockCustomBaseMinutes"
    static let customIncrementSecondsKey = "gameClockCustomIncrementSeconds"
    static let customBaseMinutesDefault = 10
    static let customIncrementSecondsDefault = 5
    static let customBaseMinutesRange = 1...180
    static let customIncrementSecondsRange = 0...60

    static var preset: ClockPreset {
        get {
            let raw = UserDefaults.standard.string(forKey: presetKey) ?? ClockPreset.off.rawValue
            return ClockPreset(rawValue: raw) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: presetKey) }
    }

    static var customBaseMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: customBaseMinutesKey)
            if UserDefaults.standard.object(forKey: customBaseMinutesKey) == nil {
                return customBaseMinutesDefault
            }
            return min(max(stored, customBaseMinutesRange.lowerBound), customBaseMinutesRange.upperBound)
        }
        set {
            UserDefaults.standard.set(
                min(max(newValue, customBaseMinutesRange.lowerBound), customBaseMinutesRange.upperBound),
                forKey: customBaseMinutesKey
            )
        }
    }

    static var customIncrementSeconds: Int {
        get {
            if UserDefaults.standard.object(forKey: customIncrementSecondsKey) == nil {
                return customIncrementSecondsDefault
            }
            let stored = UserDefaults.standard.integer(forKey: customIncrementSecondsKey)
            return min(max(stored, customIncrementSecondsRange.lowerBound), customIncrementSecondsRange.upperBound)
        }
        set {
            UserDefaults.standard.set(
                min(max(newValue, customIncrementSecondsRange.lowerBound), customIncrementSecondsRange.upperBound),
                forKey: customIncrementSecondsKey
            )
        }
    }

    static func baseSeconds(for preset: ClockPreset) -> TimeInterval {
        switch preset {
        case .off: 0
        case .custom: TimeInterval(customBaseMinutes * 60)
        case .fivePlusThree, .tenPlusFive, .fifteenPlusTen:
            preset.fixedBaseSeconds ?? 0
        }
    }

    static func incrementSeconds(for preset: ClockPreset) -> TimeInterval {
        switch preset {
        case .off: 0
        case .custom: TimeInterval(customIncrementSeconds)
        case .fivePlusThree, .tenPlusFive, .fifteenPlusTen:
            preset.fixedIncrementSeconds ?? 0
        }
    }

    /// PGN TimeControl tag value, e.g. `"300+3"`. Nil when Off.
    static func timeControlString(for preset: ClockPreset) -> String? {
        guard preset != .off else { return nil }
        let base = Int(baseSeconds(for: preset))
        let inc = Int(incrementSeconds(for: preset))
        return "\(base)+\(inc)"
    }

    /// Parse a PGN-style `"base+increment"` string into seconds.
    static func parseTimeControl(_ value: String) -> (base: TimeInterval, increment: TimeInterval)? {
        let parts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let base = Double(parts[0]),
              let increment = Double(parts[1]),
              base > 0 else { return nil }
        return (base, max(0, increment))
    }

    /// Best matching preset for a TimeControl tag, or `.custom` when it doesn't match a fixed preset.
    static func preset(matchingTimeControl value: String) -> ClockPreset? {
        guard parseTimeControl(value) != nil else { return nil }
        for preset in ClockPreset.allCases where preset != .off && preset != .custom {
            if timeControlString(for: preset) == value { return preset }
        }
        return .custom
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

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func resetToDefaults() {
        yoloConfidenceValue = yoloConfidenceDefault
        classifierConfidenceValue = classifierConfidenceDefault
    }

    private static func storedDouble(
        for key: String,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
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
        get { storedBool(for: showCaptureDiagnosticsKey, default: false) }
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
        showCaptureDiagnostics = false
        showBoardGrid = true
        showOccupancyOverlay = true
        showPieceBoxes = false
    }

    private static func storedBool(for key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
