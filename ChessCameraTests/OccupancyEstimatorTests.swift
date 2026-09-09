import CoreGraphics
import Foundation
import Testing
@testable import ChessCamera

@Test func uniformSquareIsEmptyWithoutBaseline() throws {
    let image = try makeGrayImage(size: 64, value: 128)
    let fingerprint = SquareFingerprint.make(image)
    #expect(!OccupancyHeuristic.isOccupied(fingerprint: fingerprint, baseline: nil))
}

@Test func checkerboardSquareIsOccupiedWithoutBaseline() throws {
    let image = try makeCheckerImage(size: 64)
    let fingerprint = SquareFingerprint.make(image)
    #expect(OccupancyHeuristic.isOccupied(fingerprint: fingerprint, baseline: nil))
}

@Test func occupancyUsesClassMapWhenProvided() throws {
    let gray = try makeGrayImage(size: 32, value: 200)
    let crops = [
        SquareCrop(square: ChessSquare.parse("e4")!, image: gray),
        SquareCrop(square: ChessSquare.parse("e5")!, image: gray)
    ]
    let estimator = HeuristicOccupancyEstimator()
    let occupancy = estimator.occupancy(
        crops: crops,
        classes: [
            ChessSquare.parse("e4")!: .whitePawn,
            ChessSquare.parse("e5")!: .empty
        ]
    )
    #expect(occupancy.occupied(ChessSquare.parse("e4")!))
    #expect(!occupancy.occupied(ChessSquare.parse("e5")!))
}

@Test func fenCodecStandardIsLegal() {
    #expect(FenCodec.isLegal(FenCodec.standard))
    #expect(FenCodec.isStandardStart(FenCodec.standard))
}

@Test func fenCodecRoundTripsPlacement() {
    let classes = FenCodec.standardClasses()
    let fen = FenCodec.fen(from: classes)
    #expect(FenCodec.isStandardStart(fen))
    #expect(FenCodec.parsePieces(fen)[ChessSquare.parse("e1")!] == .whiteKing)
}

@Test func pgnMoveListExtractsSans() {
    let sans = PGNMoveList.sans(from: "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0")
    #expect(sans == ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"])
}

@Test func pgnPreviewShowsFirstSixPlies() {
    let preview = PGNMoveList.preview("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Bxc6", maxPlies: 6)
    #expect(preview == "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6")
}

@Test func gridSamplerExportsSixtyFourCrops() throws {
    let image = try makeGrayImage(size: 512, value: 90)
    let crops = GridSampler.crops(from: image, orientation: .whiteAtBottom, inset: 0)
    #expect(crops.count == 64)
    #expect(crops.first?.square.algebraic == "a8")
    #expect(crops.last?.square.algebraic == "h1")
}

private func makeGrayImage(size: Int, value: UInt8) throws -> CGImage {
    let bytes = [UInt8](repeating: value, count: size * size * 4)
    return try cgImage(from: bytes, size: size)
}

private func makeCheckerImage(size: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let on = ((x / 4) + (y / 4)).isMultiple(of: 2)
            let v: UInt8 = on ? 255 : 0
            let i = (y * size + x) * 4
            bytes[i] = v
            bytes[i + 1] = v
            bytes[i + 2] = v
            bytes[i + 3] = 255
        }
    }
    return try cgImage(from: bytes, size: size)
}

private func cgImage(from bytes: [UInt8], size: Int) throws -> CGImage {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        struct ImageError: Error {}
        throw ImageError()
    }
    return image
}
