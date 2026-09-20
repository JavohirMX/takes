import CoreGraphics
import Foundation

struct CodablePoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct PersistedBoardCalibration: Codable, Equatable, Sendable {
    var topLeft: CodablePoint
    var topRight: CodablePoint
    var bottomRight: CodablePoint
    var bottomLeft: CodablePoint
    var orientationRaw: String
    var bufferWidth: Double
    var bufferHeight: Double
    var savedAt: Date

    var bufferSize: CGSize {
        CGSize(width: bufferWidth, height: bufferHeight)
    }

    var orientation: BoardOrientation? {
        BoardOrientation(rawValue: orientationRaw)
    }

    init(
        quad: Quadrilateral,
        orientation: BoardOrientation,
        bufferSize: CGSize,
        savedAt: Date = .now
    ) {
        topLeft = CodablePoint(quad.topLeft)
        topRight = CodablePoint(quad.topRight)
        bottomRight = CodablePoint(quad.bottomRight)
        bottomLeft = CodablePoint(quad.bottomLeft)
        orientationRaw = orientation.rawValue
        bufferWidth = Double(bufferSize.width)
        bufferHeight = Double(bufferSize.height)
        self.savedAt = savedAt
    }
}

enum BoardCalibrationStore {
    static let key = "persistedBoardCalibration"

    static var hasSaved: Bool {
        load() != nil
    }

    static func load() -> PersistedBoardCalibration? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedBoardCalibration.self, from: data)
    }

    static func save(_ calibration: PersistedBoardCalibration) {
        guard let data = try? JSONEncoder().encode(calibration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
