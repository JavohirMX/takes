import CoreGraphics
import Foundation
import Testing
@testable import Takes

@Suite(.serialized)
struct BoardCalibrationStoreTests {
    @Test
    func encodeDecodeRoundTripsPersistedCalibration() throws {
        try withRestoredBoardCalibrationDefaults {
            let quad = Quadrilateral(
                topLeft: CGPoint(x: 120, y: 80),
                topRight: CGPoint(x: 900, y: 90),
                bottomRight: CGPoint(x: 880, y: 700),
                bottomLeft: CGPoint(x: 100, y: 690)
            )
            let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
            let original = PersistedBoardCalibration(
                quad: quad,
                orientation: .whiteAtLeft,
                bufferSize: CGSize(width: 1920, height: 1080),
                savedAt: savedAt
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(PersistedBoardCalibration.self, from: data)

            #expect(decoded == original)
            #expect(decoded.orientation == .whiteAtLeft)
            #expect(Quadrilateral(persisted: decoded) == quad)
        }
    }

    @Test
    func storeSaveLoadAndClear() {
        withRestoredBoardCalibrationDefaults {
            #expect(!BoardCalibrationStore.hasSaved)

            let calibration = PersistedBoardCalibration(
                quad: Quadrilateral.insetRect(in: CGSize(width: 1280, height: 720)),
                orientation: .whiteAtBottom,
                bufferSize: CGSize(width: 1280, height: 720),
                savedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
            BoardCalibrationStore.save(calibration)
            #expect(BoardCalibrationStore.hasSaved)
            #expect(BoardCalibrationStore.load() == calibration)

            BoardCalibrationStore.clear()
            #expect(!BoardCalibrationStore.hasSaved)
            #expect(BoardCalibrationStore.load() == nil)
        }
    }

    @Test
    func scaledMapsCornersAcrossBufferSizes() {
        let quad = Quadrilateral(
            topLeft: CGPoint(x: 100, y: 50),
            topRight: CGPoint(x: 300, y: 50),
            bottomRight: CGPoint(x: 300, y: 250),
            bottomLeft: CGPoint(x: 100, y: 250)
        )
        let scaled = quad.scaled(
            from: CGSize(width: 400, height: 300),
            to: CGSize(width: 800, height: 600)
        )
        #expect(abs(scaled.topLeft.x - 200) < 0.01)
        #expect(abs(scaled.topLeft.y - 100) < 0.01)
        #expect(abs(scaled.topRight.x - 600) < 0.01)
        #expect(abs(scaled.topRight.y - 100) < 0.01)
        #expect(abs(scaled.bottomRight.x - 600) < 0.01)
        #expect(abs(scaled.bottomRight.y - 500) < 0.01)
        #expect(abs(scaled.bottomLeft.x - 200) < 0.01)
        #expect(abs(scaled.bottomLeft.y - 500) < 0.01)
    }

    @Test
    func scaledThenClampedStaysInBounds() {
        let quad = Quadrilateral(
            topLeft: CGPoint(x: 10, y: 10),
            topRight: CGPoint(x: 390, y: 10),
            bottomRight: CGPoint(x: 390, y: 290),
            bottomLeft: CGPoint(x: 10, y: 290)
        )
        let newSize = CGSize(width: 200, height: 100)
        let scaled = quad.scaled(from: CGSize(width: 400, height: 300), to: newSize)
            .clamped(to: newSize)
        for point in scaled.points {
            #expect(point.x >= 0)
            #expect(point.x <= newSize.width)
            #expect(point.y >= 0)
            #expect(point.y <= newSize.height)
        }
    }

    @Test
    func boardOrientationRawValuesRoundTrip() throws {
        for orientation in BoardOrientation.allCases {
            let data = try JSONEncoder().encode(orientation)
            let decoded = try JSONDecoder().decode(BoardOrientation.self, from: data)
            #expect(decoded == orientation)
            #expect(BoardOrientation(rawValue: orientation.rawValue) == orientation)
        }
    }

    @Test @MainActor
    func restoreNoOpsWhenRememberIsOff() async {
        let restore = pushBoardCalibrationDefaults()
        defer { restore() }

        BoardCalibrationSettings.rememberSetup = true
        BoardCalibrationStore.save(
            PersistedBoardCalibration(
                quad: Quadrilateral.insetRect(in: CGSize(width: 1280, height: 720)),
                orientation: .whiteAtTop,
                bufferSize: CGSize(width: 1280, height: 720),
                savedAt: Date(timeIntervalSince1970: 1_700_000_200)
            )
        )

        let model = RecordingSessionViewModel()
        model.bufferSize = CGSize(width: 1280, height: 720)
        BoardCalibrationSettings.rememberSetup = false

        let restored = await model.restorePersistedCalibrationIfPossible()
        #expect(!restored)
        #expect(model.quad == nil)
    }

    @Test @MainActor
    func restoreScalesWhenBufferSizeChanges() async {
        let restore = pushBoardCalibrationDefaults()
        defer { restore() }

        BoardCalibrationSettings.rememberSetup = true
        let savedQuad = Quadrilateral(
            topLeft: CGPoint(x: 100, y: 50),
            topRight: CGPoint(x: 300, y: 50),
            bottomRight: CGPoint(x: 300, y: 250),
            bottomLeft: CGPoint(x: 100, y: 250)
        )
        BoardCalibrationStore.save(
            PersistedBoardCalibration(
                quad: savedQuad,
                orientation: .whiteAtRight,
                bufferSize: CGSize(width: 400, height: 300),
                savedAt: Date(timeIntervalSince1970: 1_700_000_300)
            )
        )

        let model = RecordingSessionViewModel()
        model.bufferSize = CGSize(width: 800, height: 600)

        let restored = await model.restorePersistedCalibrationIfPossible()
        #expect(restored)
        #expect(model.orientation == .whiteAtRight)
        let expected = savedQuad.scaled(
            from: CGSize(width: 400, height: 300),
            to: CGSize(width: 800, height: 600)
        )
        #expect(model.quad == expected)
    }
}

private let boardCalibrationKeys = [
    BoardCalibrationStore.key,
    BoardCalibrationSettings.key,
]

private func pushBoardCalibrationDefaults() -> () -> Void {
    let defaults = UserDefaults.standard
    let saved = boardCalibrationKeys.map { ($0, defaults.object(forKey: $0)) }
    for key in boardCalibrationKeys {
        defaults.removeObject(forKey: key)
    }
    return {
        for (key, value) in saved {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

private func withRestoredBoardCalibrationDefaults(_ body: () throws -> Void) rethrows {
    let restore = pushBoardCalibrationDefaults()
    defer { restore() }
    try body()
}
