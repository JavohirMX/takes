import Foundation

/// Detects common chess opening names from initial move SAN sequences.
enum OpeningDetector {
    private struct OpeningEntry {
        let moves: [String]
        let name: String
    }

    private static let dictionary: [OpeningEntry] = [
        // Ruy Lopez
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bb5"], name: "Ruy Lopez"),
        // Italian Game
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Bc4"], name: "Italian Game"),
        // Scotch Game
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "d4"], name: "Scotch Game"),
        // Four Knights
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nc6", "Nc3", "Nf6"], name: "Four Knights Game"),
        // King's Gambit
        OpeningEntry(moves: ["e4", "e5", "f4"], name: "King’s Gambit"),
        // Vienna Game
        OpeningEntry(moves: ["e4", "e5", "Nc3"], name: "Vienna Game"),
        // Petrov Defense
        OpeningEntry(moves: ["e4", "e5", "Nf3", "Nf6"], name: "Petrov’s Defense"),
        // Philidor Defense
        OpeningEntry(moves: ["e4", "e5", "Nf3", "d6"], name: "Philidor Defense"),
        // Sicilian Defense
        OpeningEntry(moves: ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "a6"], name: "Sicilian: Najdorf"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "Nc6", "d4", "cxd4", "Nxd4", "g6"], name: "Sicilian: Accelerated Dragon"),
        OpeningEntry(moves: ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "g6"], name: "Sicilian: Dragon"),
        OpeningEntry(moves: ["e4", "c5", "c3"], name: "Sicilian: Alapin"),
        OpeningEntry(moves: ["e4", "c5"], name: "Sicilian Defense"),
        // French Defense
        OpeningEntry(moves: ["e4", "e6", "d4", "d5", "e5"], name: "French: Advance"),
        OpeningEntry(moves: ["e4", "e6", "d4", "d5"], name: "French Defense"),
        OpeningEntry(moves: ["e4", "e6"], name: "French Defense"),
        // Caro-Kann
        OpeningEntry(moves: ["e4", "c6", "d4", "d5", "e5"], name: "Caro-Kann: Advance"),
        OpeningEntry(moves: ["e4", "c6", "d4", "d5"], name: "Caro-Kann Defense"),
        OpeningEntry(moves: ["e4", "c6"], name: "Caro-Kann Defense"),
        // Scandinavian
        OpeningEntry(moves: ["e4", "d5"], name: "Scandinavian Defense"),
        // Pirc / Modern
        OpeningEntry(moves: ["e4", "d6", "d4", "Nf6", "Nc3", "g6"], name: "Pirc Defense"),
        OpeningEntry(moves: ["e4", "g6"], name: "Modern Defense"),
        // Alekhine
        OpeningEntry(moves: ["e4", "Nf6"], name: "Alekhine’s Defense"),
        // Open Game fallback
        OpeningEntry(moves: ["e4", "e5"], name: "Open Game"),
        // Queen's Gambit
        OpeningEntry(moves: ["d4", "d5", "c4", "e6"], name: "Queen’s Gambit Declined"),
        OpeningEntry(moves: ["d4", "d5", "c4", "dxc4"], name: "Queen’s Gambit Accepted"),
        OpeningEntry(moves: ["d4", "d5", "c4", "c6"], name: "Slav Defense"),
        OpeningEntry(moves: ["d4", "d5", "c4"], name: "Queen’s Gambit"),
        // London System
        OpeningEntry(moves: ["d4", "d5", "Bf4"], name: "London System"),
        OpeningEntry(moves: ["d4", "Nf6", "Bf4"], name: "London System"),
        // King's Indian
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6", "Nc3", "Bg7"], name: "King’s Indian Defense"),
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6"], name: "King’s Indian Defense"),
        // Grunfeld
        OpeningEntry(moves: ["d4", "Nf6", "c4", "g6", "Nc3", "d5"], name: "Grünfeld Defense"),
        // Nimzo-Indian
        OpeningEntry(moves: ["d4", "Nf6", "c4", "e6", "Nc3", "Bb4"], name: "Nimzo-Indian Defense"),
        // Queen's Indian
        OpeningEntry(moves: ["d4", "Nf6", "c4", "e6", "Nf3", "b6"], name: "Queen’s Indian Defense"),
        // Bogo-Indian
        OpeningEntry(moves: ["d4", "Nf6", "c4", "e6", "Nf3", "Bb4+"], name: "Bogo-Indian Defense"),
        // Dutch Defense
        OpeningEntry(moves: ["d4", "f5"], name: "Dutch Defense"),
        // Benoni
        OpeningEntry(moves: ["d4", "Nf6", "c4", "c5", "d5"], name: "Benoni Defense"),
        // English Opening
        OpeningEntry(moves: ["c4", "e5"], name: "English: King’s English"),
        OpeningEntry(moves: ["c4", "c5"], name: "English: Symmetrical"),
        OpeningEntry(moves: ["c4"], name: "English Opening"),
        // Reti Opening
        OpeningEntry(moves: ["Nf3", "d5", "c4"], name: "Réti Opening"),
        OpeningEntry(moves: ["Nf3"], name: "Réti Opening"),
        // Closed Game fallback
        OpeningEntry(moves: ["d4", "d5"], name: "Closed Game"),
        OpeningEntry(moves: ["d4"], name: "Queen’s Pawn Opening"),
        OpeningEntry(moves: ["e4"], name: "King’s Pawn Opening")
    ]

    /// Detects opening from a SAN array. Longest matching prefix wins.
    static func detect(sans: [String]) -> String? {
        guard !sans.isEmpty else { return nil }

        // Clean SANs (remove ! ? # + for comparison)
        let cleaned = sans.map { $0.replacingOccurrences(of: "[+#!?]", with: "", options: .regularExpression) }

        // Sort dictionary so longest prefixes are evaluated first
        let sorted = dictionary.sorted { $0.moves.count > $1.moves.count }
        for entry in sorted {
            if matches(prefix: entry.moves, against: cleaned) {
                return entry.name
            }
        }
        return nil
    }

    /// Detects opening from a PGN string.
    static func detect(pgn: String) -> String? {
        let sans = PGNMoveList.sans(from: pgn)
        return detect(sans: sans)
    }

    private static func matches(prefix: [String], against candidate: [String]) -> Bool {
        guard candidate.count >= prefix.count else { return false }
        for (i, move) in prefix.enumerated() {
            let cleanPrefix = move.replacingOccurrences(of: "[+#!?]", with: "", options: .regularExpression)
            if candidate[i] != cleanPrefix {
                return false
            }
        }
        return true
    }
}
