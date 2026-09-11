import Foundation

enum BoardOrientation: Sendable, Equatable, CaseIterable {
    /// Camera on White’s side. Image bottom-left is a1; files run left→right.
    case whiteAtBottom
    /// Camera on the h-file. Image top-left is a1; files run top→bottom.
    case whiteAtLeft
    /// Camera on Black’s side. Image top-right is a1; files run right→left.
    case whiteAtTop
    /// Camera on the a-file. Image bottom-right is a1; files run bottom→top.
    case whiteAtRight

    var rotatedClockwise: BoardOrientation {
        switch self {
        case .whiteAtBottom: .whiteAtLeft
        case .whiteAtLeft: .whiteAtTop
        case .whiteAtTop: .whiteAtRight
        case .whiteAtRight: .whiteAtBottom
        }
    }

    /// Maps a camera-up grid index to an algebraic square.
    func square(fileIndex: Int, rankFromImageTop: Int) -> ChessSquare {
        switch self {
        case .whiteAtBottom:
            ChessSquare(file: fileIndex, rank: 7 - rankFromImageTop)
        case .whiteAtLeft:
            ChessSquare(file: rankFromImageTop, rank: fileIndex)
        case .whiteAtTop:
            ChessSquare(file: 7 - fileIndex, rank: rankFromImageTop)
        case .whiteAtRight:
            ChessSquare(file: 7 - rankFromImageTop, rank: 7 - fileIndex)
        }
    }

    /// Inverse of `square(fileIndex:rankFromImageTop:)`.
    func imageIndices(for square: ChessSquare) -> (fileIndex: Int, rankFromImageTop: Int) {
        switch self {
        case .whiteAtBottom:
            (square.file, 7 - square.rank)
        case .whiteAtLeft:
            (square.rank, square.file)
        case .whiteAtTop:
            (7 - square.file, square.rank)
        case .whiteAtRight:
            (7 - square.rank, 7 - square.file)
        }
    }
}
