import Foundation

enum AnalysisSpeed: String, CaseIterable, Sendable, Identifiable {
    case fast
    case balanced
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .deep: "Deep"
        }
    }

    var movetimeMs: Int {
        switch self {
        case .fast: 200
        case .balanced: 500
        case .deep: 1200
        }
    }

    var threads: Int {
        switch self {
        case .fast: 1
        case .balanced: 2
        case .deep: 2
        }
    }

    var hashMB: Int {
        switch self {
        case .fast: 16
        case .balanced: 64
        case .deep: 128
        }
    }
}

enum AnalysisSettings {
    // MARK: Keys

    static let liveHintsKey = "analysisLiveHints"
    static let liveShowEvalKey = "analysisLiveShowEval"
    static let liveShowArrowKey = "analysisLiveShowArrow"

    static let postGameKey = "analysisPostGame"
    static let postShowEvalBarKey = "analysisPostShowEvalBar"
    static let postShowArrowKey = "analysisPostShowArrow"
    static let postShowPVKey = "analysisPostShowPV"
    static let postShowLabelsKey = "analysisPostShowLabels"
    static let postShowAccuracyKey = "analysisPostShowAccuracy"
    static let postShowGraphKey = "analysisPostShowGraph"

    static let speedKey = "analysisSpeed"
    static let liveMovetimeMs = 200

    // MARK: Live (default off)

    static var liveHintsEnabled: Bool {
        get { storedBool(for: liveHintsKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: liveHintsKey) }
    }

    static var liveShowEval: Bool {
        get { storedBool(for: liveShowEvalKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: liveShowEvalKey) }
    }

    static var liveShowArrow: Bool {
        get { storedBool(for: liveShowArrowKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: liveShowArrowKey) }
    }

    /// Effective: master on and sub-toggle on.
    static var effectiveLiveShowEval: Bool { liveHintsEnabled && liveShowEval }
    static var effectiveLiveShowArrow: Bool { liveHintsEnabled && liveShowArrow }

    // MARK: Post-game (default on)

    static var postGameEnabled: Bool {
        get { storedBool(for: postGameKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: postGameKey) }
    }

    static var postShowEvalBar: Bool {
        get { storedBool(for: postShowEvalBarKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: postShowEvalBarKey) }
    }

    static var postShowArrow: Bool {
        get { storedBool(for: postShowArrowKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: postShowArrowKey) }
    }

    static var postShowPV: Bool {
        get { storedBool(for: postShowPVKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: postShowPVKey) }
    }

    static var postShowLabels: Bool {
        get { storedBool(for: postShowLabelsKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: postShowLabelsKey) }
    }

    static var postShowAccuracy: Bool {
        get { storedBool(for: postShowAccuracyKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: postShowAccuracyKey) }
    }

    static var postShowGraph: Bool {
        get { storedBool(for: postShowGraphKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: postShowGraphKey) }
    }

    static var effectivePostShowEvalBar: Bool { postGameEnabled && postShowEvalBar }
    static var effectivePostShowArrow: Bool { postGameEnabled && postShowArrow }
    static var effectivePostShowPV: Bool { postGameEnabled && postShowPV }
    static var effectivePostShowLabels: Bool { postGameEnabled && postShowLabels }
    static var effectivePostShowAccuracy: Bool { postGameEnabled && postShowAccuracy }
    static var effectivePostShowGraph: Bool { postGameEnabled && postShowGraph }

    // MARK: Speed

    static var speed: AnalysisSpeed {
        get {
            let raw = UserDefaults.standard.string(forKey: speedKey) ?? AnalysisSpeed.balanced.rawValue
            return AnalysisSpeed(rawValue: raw) ?? .balanced
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: speedKey) }
    }

    // MARK: Helpers

    private static func storedBool(for key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
