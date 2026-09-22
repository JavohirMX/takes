import ChessKit
import Foundation

/// Solves for the starting board position (FEN) of a game given its recorded SAN moves
/// and the final board position. Used to recover the initial position for legacy game records
/// that were started mid-game before `initialFen` was explicitly persisted.
enum RetrogradePositionSolver {
    /// Attempts to solve for the starting FEN of a game.
    /// - Parameters:
    ///   - sans: List of moves played in the game.
    ///   - finalFen: The final position of the board at game end.
    ///   - maxNodes: Maximum search nodes to prevent freezing on large/ambiguous branches.
    /// - Returns: A valid FEN from which all `sans` can be legally played, or nil if unsolvable.
    static func solveInitialFEN(sans: [String], finalFen: String, maxNodes: Int = 2000) -> String? {
        guard !sans.isEmpty else { return finalFen }

        // 1. Fast check: is this playable from the standard chess starting position?
        if let standardEngine = try? GameEngine(fen: FenCodec.standard) {
            var canPlayAll = true
            for san in sans {
                do {
                    try standardEngine.apply(san: san)
                } catch {
                    canPlayAll = false
                    break
                }
            }
            if canPlayAll {
                let targetPlacement = FenCodec.placement(from: FenCodec.parsePieces(finalFen))
                let standardPlacement = FenCodec.placement(from: standardEngine.pieceMap())
                if targetPlacement == standardPlacement {
                    return FenCodec.standard
                }
            }
        }

        // 2. Backward retrograde search from finalFen
        var nodesEvaluated = 0
        let cleanedSANs = sans.map { cleanSAN($0) }
        guard let solvedFEN = backtrack(
            targetFen: finalFen,
            sans: cleanedSANs,
            plyIndex: cleanedSANs.count - 1,
            nodesEvaluated: &nodesEvaluated,
            maxNodes: maxNodes
        ) else {
            return nil
        }

        // 3. Verify forward from solved starting position
        if let verifier = try? GameEngine(fen: solvedFEN) {
            do {
                for san in sans {
                    try verifier.apply(san: san)
                }
                let targetPlacement = FenCodec.placement(from: FenCodec.parsePieces(finalFen))
                let resultPlacement = FenCodec.placement(from: verifier.pieceMap())
                if targetPlacement == resultPlacement {
                    return solvedFEN
                }
            } catch {
                return nil
            }
        }

        return nil
    }

    private static func cleanSAN(_ san: String) -> String {
        san.trimmingCharacters(in: CharacterSet(charactersIn: "+#!?"))
    }

    private static func backtrack(
        targetFen: String,
        sans: [String],
        plyIndex: Int,
        nodesEvaluated: inout Int,
        maxNodes: Int
    ) -> String? {
        if plyIndex < 0 {
            return targetFen
        }
        nodesEvaluated += 1
        if nodesEvaluated > maxNodes {
            return nil
        }

        let san = sans[plyIndex]
        let candidates = candidatePriorPositions(resultingFen: targetFen, san: san)

        for candidateFen in candidates {
            // Forward check: does applying san to candidateFen yield targetFen placement?
            guard let engine = try? GameEngine(fen: candidateFen) else {
                continue
            }
            do {
                try engine.apply(san: san)
            } catch {
                continue
            }

            let afterPlacement = FenCodec.placement(from: engine.pieceMap())
            let expectedPlacement = FenCodec.placement(from: FenCodec.parsePieces(targetFen))
            guard afterPlacement == expectedPlacement else {
                continue
            }

            // Recurse to previous ply
            if let result = backtrack(
                targetFen: candidateFen,
                sans: sans,
                plyIndex: plyIndex - 1,
                nodesEvaluated: &nodesEvaluated,
                maxNodes: maxNodes
            ) {
                return result
            }
        }

        return nil
    }

    private static func candidatePriorPositions(resultingFen: String, san: String) -> [String] {
        let parts = resultingFen.components(separatedBy: " ")
        guard parts.count >= 2 else { return [] }
        let currentSide = parts[1] // "w" or "b"
        let priorSide = currentSide == "w" ? "b" : "w"
        let priorColor: Piece.Color = priorSide == "w" ? .white : .black
        let opponentColor: Piece.Color = priorColor == .white ? .black : .white

        let halfmove = parts.count >= 5 ? (Int(parts[4]) ?? 0) : 0
        let fullmove = parts.count >= 6 ? (Int(parts[5]) ?? 1) : 1
        let priorFullmove = currentSide == "w" ? max(1, fullmove - 1) : fullmove
        let priorHalfmove = max(0, halfmove - 1)
        let priorClocks = "\(priorHalfmove) \(priorFullmove)"

        let currentPieces = FenCodec.parsePieces(resultingFen)

        // Handle Castling
        if san == "O-O" {
            var prior = currentPieces
            if priorColor == .white {
                guard prior[ChessSquare(file: 6, rank: 0)] == .whiteKing,
                      prior[ChessSquare(file: 5, rank: 0)] == .whiteRook else { return [] }
                prior[ChessSquare(file: 6, rank: 0)] = .empty
                prior[ChessSquare(file: 5, rank: 0)] = .empty
                prior[ChessSquare(file: 4, rank: 0)] = .whiteKing
                prior[ChessSquare(file: 7, rank: 0)] = .whiteRook
            } else {
                guard prior[ChessSquare(file: 6, rank: 7)] == .blackKing,
                      prior[ChessSquare(file: 5, rank: 7)] == .blackRook else { return [] }
                prior[ChessSquare(file: 6, rank: 7)] = .empty
                prior[ChessSquare(file: 5, rank: 7)] = .empty
                prior[ChessSquare(file: 4, rank: 7)] = .blackKing
                prior[ChessSquare(file: 7, rank: 7)] = .blackRook
            }
            return [FenCodec.fen(from: prior, sideToMove: priorSide, castling: "KQkq", clocks: priorClocks)]
        }

        if san == "O-O-O" {
            var prior = currentPieces
            if priorColor == .white {
                guard prior[ChessSquare(file: 2, rank: 0)] == .whiteKing,
                      prior[ChessSquare(file: 3, rank: 0)] == .whiteRook else { return [] }
                prior[ChessSquare(file: 2, rank: 0)] = .empty
                prior[ChessSquare(file: 3, rank: 0)] = .empty
                prior[ChessSquare(file: 4, rank: 0)] = .whiteKing
                prior[ChessSquare(file: 0, rank: 0)] = .whiteRook
            } else {
                guard prior[ChessSquare(file: 2, rank: 7)] == .blackKing,
                      prior[ChessSquare(file: 3, rank: 7)] == .blackRook else { return [] }
                prior[ChessSquare(file: 2, rank: 7)] = .empty
                prior[ChessSquare(file: 3, rank: 7)] = .empty
                prior[ChessSquare(file: 4, rank: 7)] = .blackKing
                prior[ChessSquare(file: 0, rank: 7)] = .blackRook
            }
            return [FenCodec.fen(from: prior, sideToMove: priorSide, castling: "KQkq", clocks: priorClocks)]
        }

        // Determine destination square and promotion
        var moveToken = san
        if let eqIdx = moveToken.firstIndex(of: "=") {
            moveToken = String(moveToken[..<eqIdx])
        }

        let isCapture = moveToken.contains("x")
        let destinationString = String(moveToken.suffix(2))
        guard let destSquare = ChessSquare.parse(destinationString) else { return [] }

        guard let piecePrefix = moveToken.first else { return [] }
        let isPawnMove = piecePrefix.isLowercase

        var possibleCapturedPieces: [PieceClass] = [.empty]
        if isCapture {
            if opponentColor == .white {
                possibleCapturedPieces = [.whitePawn, .whiteKnight, .whiteBishop, .whiteRook, .whiteQueen]
            } else {
                possibleCapturedPieces = [.blackPawn, .blackKnight, .blackBishop, .blackRook, .blackQueen]
            }
        }

        var results: [String] = []

        if isPawnMove {
            let movingPawn: PieceClass = priorColor == .white ? .whitePawn : .blackPawn
            var originSquares: [ChessSquare] = []

            if isCapture {
                // e.g. exd4 -> origin file is 'e'
                let originFileChar = piecePrefix
                let originFile = Int(originFileChar.asciiValue! - Character("a").asciiValue!)
                let originRank = priorColor == .white ? destSquare.rank - 1 : destSquare.rank + 1
                if originRank >= 0 && originRank < 8 && originFile >= 0 && originFile < 8 {
                    originSquares.append(ChessSquare(file: originFile, rank: originRank))
                }
            } else {
                // Non-capture pawn move (e.g. e4)
                let step1Rank = priorColor == .white ? destSquare.rank - 1 : destSquare.rank + 1
                if step1Rank >= 0 && step1Rank < 8 {
                    originSquares.append(ChessSquare(file: destSquare.file, rank: step1Rank))
                }
                // Double step
                let doubleRankTarget = priorColor == .white ? 3 : 4
                let doubleRankOrigin = priorColor == .white ? 1 : 6
                if destSquare.rank == doubleRankTarget {
                    originSquares.append(ChessSquare(file: destSquare.file, rank: doubleRankOrigin))
                }
            }

            for origin in originSquares {
                // In resultingFen, destSquare has the pawn or promoted piece
                for captured in possibleCapturedPieces {
                    var board = currentPieces
                    board[origin] = movingPawn
                    board[destSquare] = captured
                    results.append(FenCodec.fen(from: board, sideToMove: priorSide, castling: "KQkq", clocks: priorClocks))
                }
            }
        } else {
            // Piece move: N, B, R, Q, K
            let movingPiece: PieceClass
            switch piecePrefix {
            case "N": movingPiece = priorColor == .white ? .whiteKnight : .blackKnight
            case "B": movingPiece = priorColor == .white ? .whiteBishop : .blackBishop
            case "R": movingPiece = priorColor == .white ? .whiteRook : .blackRook
            case "Q": movingPiece = priorColor == .white ? .whiteQueen : .blackQueen
            case "K": movingPiece = priorColor == .white ? .whiteKing : .blackKing
            default: return []
            }

            // Disambiguation
            var disambiguation = moveToken.dropFirst()
            if isCapture, let xIdx = disambiguation.firstIndex(of: "x") {
                disambiguation = disambiguation[..<xIdx]
            } else {
                disambiguation = disambiguation.dropLast(2)
            }

            let originCandidates = candidateOriginSquares(for: movingPiece, dest: destSquare, disambiguation: String(disambiguation), in: currentPieces)

            for origin in originCandidates {
                for captured in possibleCapturedPieces {
                    var board = currentPieces
                    board[origin] = movingPiece
                    board[destSquare] = captured
                    results.append(FenCodec.fen(from: board, sideToMove: priorSide, castling: "KQkq", clocks: priorClocks))
                }
            }
        }

        return results
    }

    private static func candidateOriginSquares(
        for piece: PieceClass,
        dest: ChessSquare,
        disambiguation: String,
        in board: [ChessSquare: PieceClass]
    ) -> [ChessSquare] {
        var squares: [ChessSquare] = []

        var fileFilter: Int? = nil
        var rankFilter: Int? = nil
        for char in disambiguation {
            if char >= "a" && char <= "h" {
                fileFilter = Int(char.asciiValue! - Character("a").asciiValue!)
            } else if let r = char.wholeNumberValue, r >= 1 && r <= 8 {
                rankFilter = r - 1
            }
        }

        for file in 0..<8 {
            if let fileFilter, file != fileFilter { continue }
            for rank in 0..<8 {
                if let rankFilter, rank != rankFilter { continue }
                let sq = ChessSquare(file: file, rank: rank)
                if sq == dest { continue }
                // In resulting position, the origin square must be empty!
                if let existing = board[sq], existing != .empty { continue }

                if canPieceMove(piece: piece, from: sq, to: dest, in: board) {
                    squares.append(sq)
                }
            }
        }
        return squares
    }

    private static func canPieceMove(piece: PieceClass, from: ChessSquare, to: ChessSquare, in board: [ChessSquare: PieceClass]) -> Bool {
        let df = abs(from.file - to.file)
        let dr = abs(from.rank - to.rank)

        switch piece {
        case .whiteKnight, .blackKnight:
            return (df == 1 && dr == 2) || (df == 2 && dr == 1)
        case .whiteKing, .blackKing:
            return df <= 1 && dr <= 1
        case .whiteBishop, .blackBishop:
            if df != dr || df == 0 { return false }
            return isPathClear(from: from, to: to, in: board)
        case .whiteRook, .blackRook:
            if df != 0 && dr != 0 { return false }
            return isPathClear(from: from, to: to, in: board)
        case .whiteQueen, .blackQueen:
            if (df != dr && df != 0 && dr != 0) || (df == 0 && dr == 0) { return false }
            return isPathClear(from: from, to: to, in: board)
        default:
            return false
        }
    }

    private static func isPathClear(from: ChessSquare, to: ChessSquare, in board: [ChessSquare: PieceClass]) -> Bool {
        let stepF = (to.file - from.file).signum()
        let stepR = (to.rank - from.rank).signum()
        var curF = from.file + stepF
        var curR = from.rank + stepR
        while curF != to.file || curR != to.rank {
            let sq = ChessSquare(file: curF, rank: curR)
            if let piece = board[sq], piece != .empty {
                return false
            }
            curF += stepF
            curR += stepR
        }
        return true
    }
}
