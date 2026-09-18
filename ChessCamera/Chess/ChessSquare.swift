import Foundation

struct ChessSquare: Hashable, Sendable, Codable {
    var file: Int // 0...7
    var rank: Int // 0...7

    var algebraic: String {
        let files = Array("abcdefgh")
        return "\(files[file])\(rank + 1)"
    }

    var bitIndex: Int { rank * 8 + file }

    static func parse(_ algebraic: String) -> ChessSquare? {
        guard algebraic.count == 2,
              let f = algebraic.first,
              let r = algebraic.last,
              let file = Array("abcdefgh").firstIndex(of: f),
              let rank = Int(String(r)), rank >= 1, rank <= 8 else { return nil }
        return ChessSquare(file: file, rank: rank - 1)
    }
}

extension ChessSquare: Identifiable {
    public var id: String { algebraic }

    init(bitIndex: Int) {
        self.init(file: bitIndex % 8, rank: bitIndex / 8)
    }
}
