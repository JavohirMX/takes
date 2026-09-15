import CoreGraphics
import Foundation
import Testing
@testable import ChessCamera

@Suite(.serialized)
struct DetectionSettingsTests {
    @Test
    func detectionDefaultsWhenKeysAreMissing() {
        withRestoredDeveloperDefaults {
            #expect(DetectionSettings.yoloConfidenceValue == DetectionSettings.yoloConfidenceDefault)
            #expect(DetectionSettings.classifierConfidenceValue == DetectionSettings.classifierConfidenceDefault)
            #expect(abs(PieceDetection.confidenceThreshold - 0.25) < 0.0001)
            #expect(abs(DetectionSettings.classifierConfidence - 0.35) < 0.0001)
        }
    }

    @Test
    func overlayDefaultsWhenKeysAreMissing() {
        withRestoredDeveloperDefaults {
            #expect(DebugOverlaySettings.showYoloDots)
            #expect(DebugOverlaySettings.showCaptureDiagnostics)
            #expect(DebugOverlaySettings.showBoardGrid)
            #expect(DebugOverlaySettings.showOccupancyOverlay)
            #expect(!DebugOverlaySettings.showPieceBoxes)
        }
    }

    @Test
    func confidenceWritesAreClamped() {
        withRestoredDeveloperDefaults {
            DetectionSettings.yoloConfidenceValue = 0.01
            #expect(DetectionSettings.yoloConfidenceValue == DetectionSettings.yoloConfidenceRange.lowerBound)
            DetectionSettings.yoloConfidenceValue = 0.99
            #expect(DetectionSettings.yoloConfidenceValue == DetectionSettings.yoloConfidenceRange.upperBound)

            DetectionSettings.classifierConfidenceValue = 0.01
            #expect(
                DetectionSettings.classifierConfidenceValue
                    == DetectionSettings.classifierConfidenceRange.lowerBound
            )
            DetectionSettings.classifierConfidenceValue = 0.99
            #expect(
                DetectionSettings.classifierConfidenceValue
                    == DetectionSettings.classifierConfidenceRange.upperBound
            )
        }
    }

    @Test
    func resetRestoresStockValues() {
        withRestoredDeveloperDefaults {
            DetectionSettings.yoloConfidenceValue = 0.55
            DetectionSettings.classifierConfidenceValue = 0.60
            DebugOverlaySettings.showYoloDots = false
            DebugOverlaySettings.showCaptureDiagnostics = false
            DebugOverlaySettings.showBoardGrid = false
            DebugOverlaySettings.showOccupancyOverlay = false
            DebugOverlaySettings.showPieceBoxes = true

            DetectionSettings.resetToDefaults()
            DebugOverlaySettings.resetToDefaults()

            #expect(DetectionSettings.yoloConfidenceValue == DetectionSettings.yoloConfidenceDefault)
            #expect(DetectionSettings.classifierConfidenceValue == DetectionSettings.classifierConfidenceDefault)
            #expect(DebugOverlaySettings.showYoloDots)
            #expect(DebugOverlaySettings.showCaptureDiagnostics)
            #expect(DebugOverlaySettings.showBoardGrid)
            #expect(DebugOverlaySettings.showOccupancyOverlay)
            #expect(!DebugOverlaySettings.showPieceBoxes)
        }
    }

    @Test
    func pieceDetectionThresholdFollowsStoredValue() {
        withRestoredDeveloperDefaults {
            DetectionSettings.yoloConfidenceValue = 0.55
            #expect(abs(PieceDetection.confidenceThreshold - 0.55) < 0.0001)
        }
    }

    @Test
    func tightRectUsesPlayingSurfaceUV() {
        withRestoredDeveloperDefaults {
            let box = PieceDetection.Box(
                id: 0,
                piece: .whiteKing,
                confidence: 0.9,
                bufferRect: CGRect(x: 256, y: 448, width: 64, height: 64)
            )
            let rect = PieceDetection.tightRect(of: box, paddedImageSize: 512, margin: 0)
            #expect(rect != nil)
            #expect(abs((rect?.minX ?? -1) - 256.0 / 512.0) < 0.002)
            #expect(abs((rect?.minY ?? -1) - 448.0 / 512.0) < 0.002)
            #expect(abs((rect?.width ?? -1) - 64.0 / 512.0) < 0.002)
            #expect(abs((rect?.height ?? -1) - 64.0 / 512.0) < 0.002)
        }
    }

    @Test
    func overlayBoxesDropDetectionsBelowThreshold() {
        withRestoredDeveloperDefaults {
            DetectionSettings.yoloConfidenceValue = 0.50
            let box = PieceDetection.Box(
                id: 0,
                piece: .whitePawn,
                confidence: 0.4,
                bufferRect: CGRect(x: 0, y: 0, width: 64, height: 64)
            )
            #expect(PieceDetection.overlayBoxes(from: [box], paddedImageSize: 512, margin: 0).isEmpty)

            DetectionSettings.yoloConfidenceValue = 0.25
            #expect(PieceDetection.overlayBoxes(from: [box], paddedImageSize: 512, margin: 0).count == 1)
        }
    }
}

private let developerSettingKeys = [
    DetectionSettings.yoloConfidenceKey,
    DetectionSettings.classifierConfidenceKey,
    DebugOverlaySettings.showYoloDotsKey,
    DebugOverlaySettings.showCaptureDiagnosticsKey,
    DebugOverlaySettings.showBoardGridKey,
    DebugOverlaySettings.showOccupancyOverlayKey,
    DebugOverlaySettings.showPieceBoxesKey,
]

private func withRestoredDeveloperDefaults(_ body: () -> Void) {
    let defaults = UserDefaults.standard
    let saved = developerSettingKeys.map { ($0, defaults.object(forKey: $0)) }
    for key in developerSettingKeys {
        defaults.removeObject(forKey: key)
    }
    defer {
        for (key, value) in saved {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
    body()
}
