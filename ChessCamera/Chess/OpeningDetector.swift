import Foundation

/// Detects chess opening names and ECO codes from initial move SAN sequences.
enum OpeningDetector {
    struct OpeningEntry: Sendable {
        let moves: [String]
        let name: String
        let eco: String?

        init(moves: [String], name: String, eco: String? = nil) {
            self.moves = moves
            self.name = name
            self.eco = eco
        }
    }

    static let dictionary: [OpeningEntry] = [
        // Ruy Lopez
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6", "O-O", "Be7"], name: "Ruy Lopez: Closed", eco: "C84"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6", "O-O", "Nxe4"], name: "Ruy Lopez: Open", eco: "C80"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bb5", "Nf6"], name: "Ruy Lopez: Berlin Defense", eco: "C65"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"], name: "Ruy Lopez", eco: "C70"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bb5"], name: "Ruy Lopez", eco: "C60"),

        // Italian Game
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3", "Nf6", "d4"], name: "Italian Game: Giuoco Piano", eco: "C53"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "b4"], name: "Italian Game: Evans Gambit", eco: "C51"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Nf6"], name: "Two Knights Defense", eco: "C55"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5"], name: "Italian Game: Giuoco Piano", eco: "C50"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bc4"], name: "Italian Game", eco: "C50"),

        // Scotch Game
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "d4", "exd4", "Nxd4"], name: "Scotch Game", eco: "C45"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "d4"], name: "Scotch Game", eco: "C44"),

        // Four Knights & Three Knights
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Nc3", "Nf6"], name: "Four Knights Game", eco: "C47"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Nc3"], name: "Three Knights Game", eco: "C46"),

        // King's Gambit & Vienna
        OpeningEntry(moves: ["e4", "e5", "f4", "exf4"], name: "King’s Gambit Accepted", eco: "C34"),
        OpeningEntry(moves: ["e4", "e5", "f4", "d5"], name: "King’s Gambit: Falkbeer", eco: "C31"),
        OpeningEntry(moves: ["e4", "e5", "f4"], name: "King’s Gambit", eco: "C30"),
        OpeningEntry(moves: ["e4", "e5", "Nc3", "Nf6", "f4"], name: "Vienna Gambit", eco: "C29"),
        OpeningEntry(moves: ["e4", "e5", "Nc3"], name: "Vienna Game", eco: "C25"),

        // Petrov & Philidor
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nf6", "Nxe5", "d6"], name: "Petrov’s Defense: Classical", eco: "C42"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nf6"], name: "Petrov’s Defense", eco: "C42"),
        OpeningEntry(moves: ["e4", "e5", "Nf3", "d6"], name: "Philidor Defense", eco: "C41"),

        // Sicilian Defense
        OpeningEntry(moves: ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "a6"], name: "Sicilian: Najdorf", eco: "B90"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "g6"], name: "Sicilian: Dragon", eco: "B70"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "e6", "d4", "cxd4", "Nxd4", "a6"], name: "Sicilian: Kan", eco: "B41"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "e6", "d4", "cxd4", "Nxd4", "Nc6"], name: "Sicilian: Taimanov", eco: "B44"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "Nc6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "e5"], name: "Sicilian: Sveshnikov", eco: "B33"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "Nc6", "d4", "cxd4", "Nxd4", "g6"], name: "Sicilian: Accelerated Dragon", eco: "B35"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "d6", "Bb5+"], name: "Sicilian: Moscow", eco: "B51"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "Nc6", "Bb5"], name: "Sicilian: Rossolimo", eco: "B30"),
        OpeningEntry(moves: ["e4", "c5", "c3"], name: "Sicilian: Alapin", eco: "B22"),
        OpeningEntry(moves: ["e4", "c5", "Nc3"], name: "Sicilian: Closed", eco: "B23"),
        OpeningEntry(moves: ["e4", "c5"], name: "Sicilian Defense", eco: "B20"),

        // French Defense
        OpeningEntry(moves: ["e4", "e6", "d4", "d5", "Nc3", "Bb4"], name: "French: Winawer", eco: "C15"),
        OpeningEntry(moves: ["e4", "e6", "d4", "d5", "Nc3", "Nf6"], name: "French: Classical", eco: "C14"),
        OpeningEntry(moves: ["e4", "e6", "d4", "d5", "Nd2"], name: "French: Tarrasch", eco: "C03"),
        OpeningEntry(moves: ["e4", "e6", "d4", "d5", "e5"], name: "French: Advance", eco: "C02"),
        OpeningEntry(moves: ["e4", "e6", "d4", "d5", "exd5"], name: "French: Exchange", eco: "C01"),
        OpeningEntry(moves: ["e4", "e6", "d4", "d5"], name: "French Defense", eco: "C00"),
        OpeningEntry(moves: ["e4", "e6"], name: "French Defense", eco: "C00"),

        // Caro-Kann Defense
        OpeningEntry(moves: ["e4", "c6", "d4", "d5", "e5", "Bf5"], name: "Caro-Kann: Advance", eco: "B12"),
        OpeningEntry(moves: ["e4", "c6", "d4", "d5", "e5"], name: "Caro-Kann: Advance", eco: "B12"),
        OpeningEntry(moves: ["e4", "c6", "d4", "d5", "Nc3", "dxe4", "Nxe4", "Bf5"], name: "Caro-Kann: Classical", eco: "B18"),
        OpeningEntry(moves: ["e4", "c6", "d4", "d5", "c4"], name: "Caro-Kann: Panov", eco: "B13"),
        OpeningEntry(moves: ["e4", "c6", "d4", "d5", "exd5"], name: "Caro-Kann: Exchange", eco: "B13"),
        OpeningEntry(moves: ["e4", "c6", "d4", "d5"], name: "Caro-Kann Defense", eco: "B10"),
        OpeningEntry(moves: ["e4", "c6"], name: "Caro-Kann Defense", eco: "B10"),

        // Scandinavian, Pirc, Alekhine
        OpeningEntry(moves: ["e4", "d5", "exd5", "Qxd5", "Nc3", "Qa5"], name: "Scandinavian: Main Line", eco: "B01"),
        OpeningEntry(moves: ["e4", "d5"], name: "Scandinavian Defense", eco: "B01"),
        OpeningEntry(moves: ["e4", "d6", "d4", "Nf6", "Nc3", "g6"], name: "Pirc Defense", eco: "B07"),
        OpeningEntry(moves: ["e4", "g6"], name: "Modern Defense", eco: "B06"),
        OpeningEntry(moves: ["e4", "Nf6", "e5", "Nd5"], name: "Alekhine’s Defense", eco: "B02"),
        OpeningEntry(moves: ["e4", "Nf6"], name: "Alekhine’s Defense", eco: "B02"),
        OpeningEntry(moves: ["e4", "e5"], name: "Open Game", eco: "C20"),

        // Queen's Gambit
        OpeningEntry(moves: ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "Bg5", "Be7", "e3", "O-O"], name: "Queen’s Gambit Declined", eco: "D55"),
        OpeningEntry(moves: ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "cxd5"], name: "QGD: Exchange", eco: "D35"),
        OpeningEntry(moves: ["d4", "d5", "c4", "e6"], name: "Queen’s Gambit Declined", eco: "D30"),
        OpeningEntry(moves: ["d4", "d5", "c4", "dxc4"], name: "Queen’s Gambit Accepted", eco: "D20"),
        OpeningEntry(moves: ["d4", "d5", "c4", "c6", "Nf3", "Nf6", "Nc3", "dxc4"], name: "Slav Defense: Accepted", eco: "D15"),
        OpeningEntry(moves: ["d4", "d5", "c4", "c6", "Nf3", "Nf6", "e3"], name: "Semi-Slav Defense", eco: "D43"),
        OpeningEntry(moves: ["d4", "d5", "c4", "c6"], name: "Slav Defense", eco: "D10"),
        OpeningEntry(moves: ["d4", "d5", "c4"], name: "Queen’s Gambit", eco: "D06"),

        // London System & Queen's Pawn
        OpeningEntry(moves: ["d4", "d5", "Bf4", "Nf6", "e3"], name: "London System", eco: "D00"),
        OpeningEntry(moves: ["d4", "Nf6", "Bf4", "d5", "e3"], name: "London System", eco: "A46"),
        OpeningEntry(moves: ["d4", "d5", "Bf4"], name: "London System", eco: "D00"),
        OpeningEntry(moves: ["d4", "Nf6", "Bf4"], name: "London System", eco: "A46"),
        OpeningEntry(moves: ["d4", "d5", "Nf3", "Nf6", "e3"], name: "Colle System", eco: "D05"),

        // King's Indian & Grünfeld
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6", "Nc3", "Bg7", "e4", "d6", "Nf3", "O-O", "Be2", "e5"], name: "King’s Indian: Classical", eco: "E97"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6", "Nc3", "Bg7", "e4", "d6", "f3"], name: "King’s Indian: Sämisch", eco: "E80"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6", "Nc3", "Bg7"], name: "King’s Indian Defense", eco: "E60"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6", "Nc3", "d5", "cxd5", "Nxd5", "e4"], name: "Grünfeld: Exchange", eco: "D85"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6", "Nc3", "d5"], name: "Grünfeld Defense", eco: "D80"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6"], name: "King’s Indian", eco: "E60"),

        // Indian Defenses
        OpeningEntry(moves: ["d4", "Nf6", "c4", "e6", "Nc3", "Bb4"], name: "Nimzo-Indian Defense", eco: "E20"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "e6", "Nf3", "b6"], name: "Queen’s Indian Defense", eco: "E12"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "e6", "Nf3", "Bb4+"], name: "Bogo-Indian Defense", eco: "E11"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "c5", "d5", "e6"], name: "Modern Benoni", eco: "A60"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "c5", "d5", "b5"], name: "Benko Gambit", eco: "A57"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "c5", "d5"], name: "Benoni Defense", eco: "A56"),
        OpeningEntry(moves: ["d4", "f5"], name: "Dutch Defense", eco: "A80"),

        // English & Réti
        OpeningEntry(moves: ["c4", "e5", "Nc3", "Nf6"], name: "English: Four Knights", eco: "A28"),
        OpeningEntry(moves: ["c4", "e5"], name: "English: King’s English", eco: "A20"),
        OpeningEntry(moves: ["c4", "c5"], name: "English: Symmetrical", eco: "A30"),
        OpeningEntry(moves: ["c4", "Nf6"], name: "English: Anglo-Indian", eco: "A15"),
        OpeningEntry(moves: ["c4"], name: "English Opening", eco: "A10"),
        OpeningEntry(moves: ["Nf3", "d5", "c4"], name: "Réti Opening", eco: "A09"),
        OpeningEntry(moves: ["Nf3", "Nf6", "g3"], name: "King’s Indian Attack", eco: "A07"),
        OpeningEntry(moves: ["Nf3"], name: "Réti Opening", eco: "A04"),

        // Fallbacks
        OpeningEntry(moves: ["d4", "d5"], name: "Closed Game", eco: "D00"),
        OpeningEntry(moves: ["d4"], name: "Queen’s Pawn Opening", eco: "A40"),
        OpeningEntry(moves: ["e4"], name: "King’s Pawn Opening", eco: "B00")
    ]

    /// Detects opening from a SAN array. Longest matching prefix wins.
    static func detect(sans: [String]) -> String? {
        detectDetails(sans: sans)?.name
    }

    /// Detects opening name and ECO code from a SAN array.
    static func detectDetails(sans: [String]) -> (name: String, eco: String?)? {
        guard !sans.isEmpty else { return nil }
        let cleaned = sans.map { cleanSAN($0) }
        let sorted = dictionary.sorted { $0.moves.count > $1.moves.count }
        for entry in sorted {
            if matches(prefix: entry.moves, against: cleaned) {
                return (entry.name, entry.eco)
            }
        }
        return nil
    }

    /// Detects opening from a PGN string.
    static func detect(pgn: String) -> String? {
        let sans = PGNMoveList.sans(from: pgn)
        return detect(sans: sans)
    }

    /// True if the move at `plyIndex` is theoretical book move found in an opening line.
    static func isBookMove(sans: [String], at plyIndex: Int) -> Bool {
        guard plyIndex >= 0, plyIndex < sans.count else { return false }
        let prefix = Array(sans.prefix(plyIndex + 1)).map { cleanSAN($0) }
        for entry in dictionary where entry.moves.count > plyIndex {
            if matches(prefix: prefix, against: entry.moves) {
                return true
            }
        }
        return false
    }

    private static func cleanSAN(_ san: String) -> String {
        san.replacingOccurrences(of: "[+#!?]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(prefix: [String], against candidate: [String]) -> Bool {
        guard candidate.count >= prefix.count else { return false }
        for (i, move) in prefix.enumerated() {
            if candidate[i] != cleanSAN(move) {
                return false
            }
        }
        return true
    }
}
