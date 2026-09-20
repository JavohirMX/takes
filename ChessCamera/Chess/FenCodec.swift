import ChessKit
import Foundation

enum FenCodec {
    static let standard = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    static func standardClasses() -> [ChessSquare: PieceClass] {
        parsePieces(standard)
    }

    static func fen(
        from classes: [ChessSquare: PieceClass],
        sideToMove: String = "w",
        castling: String = "KQkq",
        enPassant: String = "-",
        clocks: String = "0 1"
    ) -> String {
        "\(placement(from: classes)) \(sideToMove) \(castling) \(enPassant) \(clocks)"
    }

    static func placement(from classes: [ChessSquare: PieceClass]) -> String {
        var ranks: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var empty = 0
            var row = ""
            for file in 0..<8 {
                let square = ChessSquare(file: file, rank: rank)
                if let piece = classes[square], piece != .empty, !piece.fenLetter.isEmpty {
                    if empty > 0 {
                        row += String(empty)
                        empty = 0
                    }
                    row += piece.fenLetter
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            ranks.append(row)
        }
        return ranks.joined(separator: "/")
    }

    static func parsePieces(_ fen: String) -> [ChessSquare: PieceClass] {
        let placement = fen.split(separator: " ").first.map(String.init) ?? fen
        var pieces: [ChessSquare: PieceClass] = [:]
        let ranks = placement.split(separator: "/")
        for (rankOffset, rankString) in ranks.enumerated() {
            let rank = 7 - rankOffset
            var file = 0
            for character in rankString {
                if let empty = character.wholeNumberValue {
                    file += empty
                    continue
                }
                if let piece = PieceClass.fromFenLetter(character), file < 8, rank >= 0 {
                    pieces[ChessSquare(file: file, rank: rank)] = piece
                    file += 1
                }
            }
        }
        return pieces
    }

    static func isLegal(_ fen: String) -> Bool {
        Position(fen: fen) != nil
    }

    static func isStandardStart(_ fen: String) -> Bool {
        let placement = fen.split(separator: " ").first.map(String.init) ?? fen
        let standardPlacement = standard.split(separator: " ").first.map(String.init) ?? standard
        return placement == standardPlacement
    }

    /// Re-keys classified pieces from one camera orientation to another without re-running ML.
    static func remapped(
        _ classes: [ChessSquare: PieceClass],
        from: BoardOrientation,
        to: BoardOrientation
    ) -> [ChessSquare: PieceClass] {
        guard from != to else { return classes }
        var remapped: [ChessSquare: PieceClass] = [:]
        remapped.reserveCapacity(classes.count)
        for (square, piece) in classes {
            let image = from.imageIndices(for: square)
            remapped[to.square(fileIndex: image.fileIndex, rankFromImageTop: image.rankFromImageTop)] = piece
        }
        return remapped
    }

    /// Infers which image edge is White from the white king’s position.
    /// `classifiedAs` is the orientation used to key `classes`.
    static func inferOrientation(
        from classes: [ChessSquare: PieceClass],
        classifiedAs: BoardOrientation = .whiteAtBottom
    ) -> BoardOrientation {
        let whiteKings = classes.filter { $0.value == .whiteKing }.map(\.key)
        guard let king = whiteKings.first else { return .whiteAtBottom }
        let image = classifiedAs.imageIndices(for: king)
        let distBottom = 7 - image.rankFromImageTop
        let distTop = image.rankFromImageTop
        let distLeft = image.fileIndex
        let distRight = 7 - image.fileIndex
        let best = min(distBottom, distTop, distLeft, distRight)
        if distBottom == best { return .whiteAtBottom }
        if distTop == best { return .whiteAtTop }
        if distLeft == best { return .whiteAtLeft }
        return .whiteAtRight
    }
}

enum PGNMoveList {
    static func sans(from pgn: String) -> [String] {
        var text = pgn
        while let start = text.firstIndex(of: "{") {
            if let end = text[start...].firstIndex(of: "}") {
                text.removeSubrange(start...end)
            } else {
                break
            }
        }
        let withoutHeaders = text
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("[") }
            .joined(separator: " ")

        let results: Set<String> = ["1-0", "0-1", "1/2-1/2", "½-½", "*"]
        var moves: [String] = []
        for raw in withoutHeaders.split(whereSeparator: \.isWhitespace) {
            var token = String(raw)
            if results.contains(token) { continue }
            if token.hasSuffix(".") && token.dropLast().allSatisfy(\.isNumber) { continue }
            if let range = token.range(of: "...") {
                token = String(token[range.upperBound...])
                if token.isEmpty { continue }
            } else if token.last == "." {
                continue
            }
            if token.isEmpty { continue }
            moves.append(token)
        }
        return moves
    }

    /// Elapsed-move-time seconds from `{[%emt H:MM:SS]}` comments, in ply order.
    static func emtSeconds(from pgn: String) -> [TimeInterval] {
        var times: [TimeInterval] = []
        var search = pgn[...]
        while let start = search.range(of: "[%emt ") {
            let after = search[start.upperBound...]
            guard let end = after.firstIndex(of: "]") else { break }
            let body = String(after[..<end])
            if let seconds = parseEMTBody(body) {
                times.append(seconds)
            }
            search = after[end...]
        }
        return times
    }

    /// Movetext with `{[%emt H:MM:SS]}` after each ply that has a time.
    static func annotatedMovetext(
        sans: [String],
        moveTimes: [TimeInterval],
        result: String = "*"
    ) -> String {
        guard !sans.isEmpty else { return result }
        var parts: [String] = []
        for (index, san) in sans.enumerated() {
            if index.isMultiple(of: 2) {
                parts.append("\(index / 2 + 1).")
            }
            var token = san
            if index < moveTimes.count {
                let emt = MoveThinkTimer.formatEMT(moveTimes[index])
                token += " {[%emt \(emt)]}"
            }
            parts.append(token)
        }
        parts.append(result)
        return parts.joined(separator: " ")
    }

    private static func parseEMTBody(_ body: String) -> TimeInterval? {
        let parts = body.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let hours = parts[0]
        let minutes = parts[1]
        let seconds = parts[2]
        guard hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else { return nil }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    static func preview(_ pgn: String, maxPlies: Int = 6) -> String {
        preview(sans: sans(from: pgn), maxPlies: maxPlies, trailing: false)
    }

    static func preview(sans: [String], maxPlies: Int = 6, trailing: Bool = true) -> String {
        guard !sans.isEmpty else { return "" }
        let start: Int
        let slice: ArraySlice<String>
        if trailing, sans.count > maxPlies {
            start = sans.count - maxPlies
            slice = sans.suffix(maxPlies)
        } else {
            start = 0
            slice = sans.prefix(maxPlies)
        }
        var parts: [String] = []
        for (offset, san) in slice.enumerated() {
            let index = start + offset
            if index.isMultiple(of: 2) {
                parts.append("\(index / 2 + 1). \(san)")
            } else if parts.isEmpty {
                parts.append("\(index / 2 + 1)... \(san)")
            } else {
                parts.append(san)
            }
        }
        return parts.joined(separator: " ")
    }
}
