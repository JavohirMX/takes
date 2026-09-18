import CoreGraphics
import Foundation
import Testing
@testable import Takes

@Test func centerCropSquareWiderFrame() {
    let crop = HeatmapCornerDecode.centerCropSquare(srcSize: CGSize(width: 1920, height: 1080))
    #expect(abs(crop.width - 1080) < 0.01)
    #expect(abs(crop.height - 1080) < 0.01)
    #expect(abs(crop.minX - 420) < 0.01)
    #expect(abs(crop.minY) < 0.01)
}

@Test func centerCropSquareTallerFrame() {
    let crop = HeatmapCornerDecode.centerCropSquare(srcSize: CGSize(width: 720, height: 1280))
    #expect(abs(crop.width - 720) < 0.01)
    #expect(abs(crop.height - 720) < 0.01)
    #expect(abs(crop.minX) < 0.01)
    #expect(abs(crop.minY - 280) < 0.01)
}

@Test func mapPeakRoundTripsCropCorners() {
    let buffer = CGSize(width: 1000, height: 800)
    let crop = HeatmapCornerDecode.centerCropSquare(srcSize: buffer)
    let tl = HeatmapCornerDecode.mapPeakToBuffer(peakIn128: .zero, cropRect: crop)
    let br = HeatmapCornerDecode.mapPeakToBuffer(peakIn128: CGPoint(x: 128, y: 128), cropRect: crop)
    #expect(abs(tl.x - crop.minX) < 0.01)
    #expect(abs(tl.y - crop.minY) < 0.01)
    #expect(abs(br.x - crop.maxX) < 0.01)
    #expect(abs(br.y - crop.maxY) < 0.01)
}

@Test func argmaxPeaksFindPlantedCorners() {
    let h = 8
    let w = 8
    var corners = [Float](repeating: 0, count: h * w * 4)
    func set(_ x: Int, _ y: Int, _ c: Int, _ v: Float) {
        corners[(y * w + x) * 4 + c] = v
    }
    set(1, 1, 0, 0.9) // TL
    set(6, 1, 1, 0.8) // TR
    set(6, 6, 2, 0.7) // BR
    set(1, 6, 3, 0.6) // BL
    let peaks = HeatmapCornerDecode.argmaxPeaks(corners: corners, height: h, width: w)
    #expect(peaks[0] == HeatmapCornerDecode.Peak(x: 1, y: 1, score: 0.9))
    #expect(peaks[1] == HeatmapCornerDecode.Peak(x: 6, y: 1, score: 0.8))
    #expect(peaks[2] == HeatmapCornerDecode.Peak(x: 6, y: 6, score: 0.7))
    #expect(peaks[3] == HeatmapCornerDecode.Peak(x: 1, y: 6, score: 0.6))
}

@Test func quadFromPeaksBuildsOrderedQuad() {
    let buffer = CGSize(width: 1280, height: 720)
    let crop = HeatmapCornerDecode.centerCropSquare(srcSize: buffer)
    let peaks = [
        HeatmapCornerDecode.Peak(x: 10, y: 10, score: 0.9),
        HeatmapCornerDecode.Peak(x: 110, y: 12, score: 0.9),
        HeatmapCornerDecode.Peak(x: 108, y: 110, score: 0.9),
        HeatmapCornerDecode.Peak(x: 12, y: 108, score: 0.9)
    ]
    let quad = HeatmapCornerDecode.quadFromPeaks(peaks, cropRect: crop, bufferSize: buffer)
    #expect(quad != nil)
    #expect(quad!.topLeft.x < quad!.topRight.x)
    #expect(quad!.topLeft.y < quad!.bottomLeft.y)
}

@Test func quadFromPeaksRejectsWeakScores() {
    let buffer = CGSize(width: 1280, height: 720)
    let crop = HeatmapCornerDecode.centerCropSquare(srcSize: buffer)
    let peaks = [
        HeatmapCornerDecode.Peak(x: 10, y: 10, score: 0.01),
        HeatmapCornerDecode.Peak(x: 110, y: 12, score: 0.9),
        HeatmapCornerDecode.Peak(x: 108, y: 110, score: 0.9),
        HeatmapCornerDecode.Peak(x: 12, y: 108, score: 0.9)
    ]
    #expect(HeatmapCornerDecode.quadFromPeaks(peaks, cropRect: crop, bufferSize: buffer) == nil)
}
