import CoreML
import Foundation
import Vision

protocol PieceClassifier: Sendable {
    func classify(_ crop: SquareCrop) async -> (PieceClass, confidence: Float)
}

enum PieceClassifierError: Error, Equatable {
    case modelMissing
    case predictionFailed
}

/// Loads a bundled Create ML image classifier when present; otherwise `loadBundled()` returns nil.
final class CoreMLPieceClassifier: PieceClassifier, @unchecked Sendable {
    private let model: VNCoreMLModel

    static func loadBundled() -> CoreMLPieceClassifier? {
        let bundle = Bundle.main
        let url =
            bundle.url(forResource: "PieceClassifier", withExtension: "mlmodelc")
            ?? bundle.url(forResource: "PieceClassifier", withExtension: "mlmodel")
        guard let url else { return nil }
        do {
            let mlModel = try MLModel(contentsOf: url)
            let vnModel = try VNCoreMLModel(for: mlModel)
            return CoreMLPieceClassifier(model: vnModel)
        } catch {
            return nil
        }
    }

    init(model: VNCoreMLModel) {
        self.model = model
    }

    func classify(_ crop: SquareCrop) async -> (PieceClass, confidence: Float) {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: crop.image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return (.empty, 0)
        }
        guard let observation = request.results?.first as? VNClassificationObservation,
              let piece = PieceClass.fromClassifierLabel(observation.identifier) else {
            return (.empty, 0)
        }
        return (piece, observation.confidence)
    }
}

extension PieceClass {
    var fenLetter: String {
        switch self {
        case .empty: ""
        case .whitePawn: "P"
        case .whiteKnight: "N"
        case .whiteBishop: "B"
        case .whiteRook: "R"
        case .whiteQueen: "Q"
        case .whiteKing: "K"
        case .blackPawn: "p"
        case .blackKnight: "n"
        case .blackBishop: "b"
        case .blackRook: "r"
        case .blackQueen: "q"
        case .blackKing: "k"
        }
    }

    var glyph: String {
        switch self {
        case .empty: ""
        case .whiteKing: "♔"
        case .whiteQueen: "♕"
        case .whiteRook: "♖"
        case .whiteBishop: "♗"
        case .whiteKnight: "♘"
        case .whitePawn: "♙"
        case .blackKing: "♚"
        case .blackQueen: "♛"
        case .blackRook: "♜"
        case .blackBishop: "♝"
        case .blackKnight: "♞"
        case .blackPawn: "♟"
        }
    }

    var isWhite: Bool {
        switch self {
        case .whitePawn, .whiteKnight, .whiteBishop, .whiteRook, .whiteQueen, .whiteKing: true
        default: false
        }
    }

    var accessibilityName: String {
        switch self {
        case .empty: "empty"
        case .whitePawn: "white pawn"
        case .whiteKnight: "white knight"
        case .whiteBishop: "white bishop"
        case .whiteRook: "white rook"
        case .whiteQueen: "white queen"
        case .whiteKing: "white king"
        case .blackPawn: "black pawn"
        case .blackKnight: "black knight"
        case .blackBishop: "black bishop"
        case .blackRook: "black rook"
        case .blackQueen: "black queen"
        case .blackKing: "black king"
        }
    }

    func nextCycled() -> PieceClass {
        let all = PieceClass.allCases
        guard let index = all.firstIndex(of: self) else { return .empty }
        return all[(index + 1) % all.count]
    }

    static func fromFenLetter(_ letter: Character) -> PieceClass? {
        switch letter {
        case "P": .whitePawn
        case "N": .whiteKnight
        case "B": .whiteBishop
        case "R": .whiteRook
        case "Q": .whiteQueen
        case "K": .whiteKing
        case "p": .blackPawn
        case "n": .blackKnight
        case "b": .blackBishop
        case "r": .blackRook
        case "q": .blackQueen
        case "k": .blackKing
        default: nil
        }
    }

    static func fromClassifierLabel(_ label: String) -> PieceClass? {
        let key = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        switch key {
        case "empty", "blank", "none": return .empty
        case "whitepawn", "wp", "p": return .whitePawn
        case "whiteknight", "wn", "n": return .whiteKnight
        case "whitebishop", "wb", "b": return .whiteBishop
        case "whiterook", "wr", "r": return .whiteRook
        case "whitequeen", "wq", "q": return .whiteQueen
        case "whiteking", "wk", "k": return .whiteKing
        case "blackpawn", "bp": return .blackPawn
        case "blackknight", "bn": return .blackKnight
        case "blackbishop", "bb": return .blackBishop
        case "blackrook", "br": return .blackRook
        case "blackqueen", "bq": return .blackQueen
        case "blackking", "bk": return .blackKing
        default:
            return PieceClass(rawValue: label) ?? PieceClass(rawValue: key)
        }
    }
}
