import Testing
@testable import ChessCamera

@Suite
struct BoardAppearanceTests {
    @Test
    func defaultStyleIsTournament() {
        #expect(BoardAppearance.defaultStyle == .tournament)
        #expect(BoardAppearance.styleKey == "boardStyle")
    }

    @Test
    func everyNonEmptyPieceHasAnAssetName() {
        for piece in PieceClass.allCases where piece != .empty {
            #expect(piece.assetName != nil)
        }
        #expect(PieceClass.empty.assetName == nil)
    }

    @Test
    func styleTitlesAreUnique() {
        let titles = BoardStyle.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
    }
}
