import CoreGraphics
import Testing
@testable import Takes

@Test func a1IsBottomLeftWhenWhiteAtBottom() {
    let r = GridSampler.rect(
        fileIndex: 0,
        rankFromImageTop: 7,
        imageSize: 512,
        inset: 0
    )
    #expect(r.midX == 32)
    #expect(r.midY == CGFloat(512 - 32))
}

@Test func orientationMapsImageRankToA1() {
    let sq = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 7,
        orientation: .whiteAtBottom
    )
    #expect(sq.algebraic == "a1")
}

@Test func whiteAtTopMapsImageTopRightToA1() {
    let sq = GridSampler.square(
        fileIndex: 7,
        rankFromImageTop: 0,
        orientation: .whiteAtTop
    )
    #expect(sq.algebraic == "a1")
}

@Test func whiteAtTopMapsImageTopLeftToH1() {
    let sq = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 0,
        orientation: .whiteAtTop
    )
    #expect(sq.algebraic == "h1")
}

@Test func whiteAtLeftMapsImageTopLeftToA1() {
    let a1 = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 0,
        orientation: .whiteAtLeft
    )
    #expect(a1.algebraic == "a1")
    let h1 = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 7,
        orientation: .whiteAtLeft
    )
    #expect(h1.algebraic == "h1")
    let a8 = GridSampler.square(
        fileIndex: 7,
        rankFromImageTop: 0,
        orientation: .whiteAtLeft
    )
    #expect(a8.algebraic == "a8")
}

@Test func whiteAtRightMapsImageBottomRightToA1() {
    let a1 = GridSampler.square(
        fileIndex: 7,
        rankFromImageTop: 7,
        orientation: .whiteAtRight
    )
    #expect(a1.algebraic == "a1")
    let h1 = GridSampler.square(
        fileIndex: 7,
        rankFromImageTop: 0,
        orientation: .whiteAtRight
    )
    #expect(h1.algebraic == "h1")
    let a8 = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 7,
        orientation: .whiteAtRight
    )
    #expect(a8.algebraic == "a8")
}

@Test func imageIndicesRoundTripForEveryOrientation() {
    let a1 = ChessSquare(file: 0, rank: 0)
    for orientation in BoardOrientation.allCases {
        let image = GridSampler.imageIndices(for: a1, orientation: orientation)
        let mapped = GridSampler.square(
            fileIndex: image.fileIndex,
            rankFromImageTop: image.rankFromImageTop,
            orientation: orientation
        )
        #expect(mapped.algebraic == "a1")
    }
}

@Test func pointAtA1CenterMapsWhenWhiteAtBottom() {
    let sq = GridSampler.square(
        containing: CGPoint(x: 32, y: 480),
        imageSize: 512,
        orientation: .whiteAtBottom
    )
    #expect(sq?.algebraic == "a1")
}

@Test func pointAtH8CenterMapsWhenWhiteAtBottom() {
    let sq = GridSampler.square(
        containing: CGPoint(x: 480, y: 32),
        imageSize: 512,
        orientation: .whiteAtBottom
    )
    #expect(sq?.algebraic == "h8")
}

@Test func pointAtImageTopRightIsA1WhenWhiteAtTop() {
    let sq = GridSampler.square(
        containing: CGPoint(x: 480, y: 32),
        imageSize: 512,
        orientation: .whiteAtTop
    )
    #expect(sq?.algebraic == "a1")
}

@Test func pointOutsideBoardIsNil() {
    #expect(
        GridSampler.square(
            containing: CGPoint(x: -1, y: 32),
            imageSize: 512,
            orientation: .whiteAtBottom
        ) == nil
    )
}

@Test func pointNearBorderClampsWithTolerance() {
    // -5px is within 3.5% (17.9px) of 512px
    let nearLeft = GridSampler.square(
        containing: CGPoint(x: -5, y: 480),
        imageSize: 512,
        orientation: .whiteAtBottom,
        borderToleranceFraction: 0.035
    )
    #expect(nearLeft?.algebraic == "a1")

    // 515px is within 3.5% (17.9px) of 512px
    let nearRight = GridSampler.square(
        containing: CGPoint(x: 515, y: 32),
        imageSize: 512,
        orientation: .whiteAtBottom,
        borderToleranceFraction: 0.035
    )
    #expect(nearRight?.algebraic == "h8")

    // -30px is outside tolerance and returns nil
    let farOutside = GridSampler.square(
        containing: CGPoint(x: -30, y: 32),
        imageSize: 512,
        orientation: .whiteAtBottom,
        borderToleranceFraction: 0.035
    )
    #expect(farOutside == nil)
}

@Test func visionBoxBottomCenterMapsToA1() {
    let box = CGRect(x: 0, y: 0, width: 0.125, height: 0.125)
    let point = PieceDetection.imagePoint(fromVisionBox: box, imageWidth: 512, imageHeight: 512)
    let sq = GridSampler.square(
        containing: point,
        imageSize: 512,
        orientation: .whiteAtBottom
    )
    #expect(sq?.algebraic == "a1")
}

@Test func higherConfidenceWinsTheSquare() {
    let a1 = ChessSquare(file: 0, rank: 0)
    let classes = PieceDetection.classes(
        from: [
            PieceDetection.Candidate(square: a1, piece: .whitePawn, confidence: 0.4),
            PieceDetection.Candidate(square: a1, piece: .whiteQueen, confidence: 0.9),
            PieceDetection.Candidate(square: a1, piece: .blackPawn, confidence: 0.2),
        ]
    )
    #expect(classes[a1] == .whiteQueen)
    #expect(classes[ChessSquare(file: 1, rank: 0)] == .empty)
    #expect(classes.count == 64)
}

@Test func yoloBottomCenterMapsToA1() {
    let names = [
        "black-bishop", "black-king", "black-knight", "black-pawn",
        "black-queen", "black-rook", "white-bishop", "white-king",
        "white-knight", "white-pawn", "white-queen", "white-rook",
    ]
    let candidate = PieceDetection.candidate(
        yoloCenterX: 32,
        centerY: 448,
        height: 64,
        classIndex: 9,
        confidence: 0.8,
        classNames: names,
        imgsz: 512,
        imageWidth: 512,
        imageHeight: 512,
        orientation: .whiteAtBottom
    )
    #expect(candidate?.square.algebraic == "a1")
    #expect(candidate?.piece == .whitePawn)
}

@Test func visionBoxConvertsToTopLeftBufferRect() {
    let box = CGRect(x: 0, y: 0, width: 0.125, height: 0.125)
    let rect = PieceDetection.bufferRect(fromVisionBox: box, imageWidth: 512, imageHeight: 512)
    #expect(abs(rect.origin.x) < 0.01)
    #expect(abs(rect.origin.y - 448) < 0.01)
    #expect(abs(rect.width - 64) < 0.01)
    #expect(abs(rect.height - 64) < 0.01)
}

@Test func yoloLetterboxRectMapsToImageCenter() {
    let rect = PieceDetection.bufferRect(
        yoloCenterX: 320,
        centerY: 320,
        width: 100,
        height: 50,
        imgsz: 640,
        imageWidth: 640,
        imageHeight: 480
    )
    #expect(abs(rect.midX - 320) < 0.5)
    #expect(abs(rect.midY - 240) < 0.5)
    #expect(abs(rect.width - 100) < 0.5)
    #expect(abs(rect.height - 50) < 0.5)
}

@Test func nmsKeepsHigherConfidenceOverlap() {
    let high = PieceDetection.Box(
        id: 0,
        piece: .whitePawn,
        confidence: 0.9,
        bufferRect: CGRect(x: 0, y: 0, width: 100, height: 100)
    )
    let low = PieceDetection.Box(
        id: 1,
        piece: .whiteQueen,
        confidence: 0.4,
        bufferRect: CGRect(x: 10, y: 10, width: 100, height: 100)
    )
    let kept = PieceDetection.nms([high, low])
    #expect(kept.count == 1)
    #expect(kept[0].piece == .whitePawn)
    #expect(kept[0].id == 0)
}

@Test func occupancyNMSKeepsMoreThanOverlayCap() {
    var boxes: [PieceDetection.Box] = []
    for index in 0..<33 {
        boxes.append(
            PieceDetection.Box(
                id: index,
                piece: .whitePawn,
                confidence: 0.9,
                bufferRect: CGRect(x: CGFloat(index) * 80, y: 0, width: 40, height: 40)
            )
        )
    }
    let overlay = PieceDetection.nms(boxes, maxCount: PieceDetection.maxOverlayBoxes)
    #expect(overlay.count == PieceDetection.maxOverlayBoxes)
    let occupancy = PieceDetection.nms(boxes, maxCount: PieceDetection.maxOccupancyBoxes)
    #expect(occupancy.count == 33)
}

@Test func occupancyIgnoresClassAndDropsOutsideQuad() {
    let quad = Quadrilateral(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 800, y: 0),
        bottomRight: CGPoint(x: 800, y: 800),
        bottomLeft: CGPoint(x: 0, y: 800)
    )
    let a1 = PieceDetection.Box(
        id: 0,
        piece: .whitePawn,
        confidence: 0.9,
        bufferRect: CGRect(x: 20, y: 650, width: 60, height: 100)
    )
    let a1WrongType = PieceDetection.Box(
        id: 1,
        piece: .blackQueen,
        confidence: 0.4,
        bufferRect: CGRect(x: 22, y: 652, width: 56, height: 96)
    )
    let h8 = PieceDetection.Box(
        id: 2,
        piece: .whiteKing,
        confidence: 0.8,
        bufferRect: CGRect(x: 730, y: 8, width: 50, height: 40)
    )
    let offBoard = PieceDetection.Box(
        id: 3,
        piece: .whiteRook,
        confidence: 0.99,
        bufferRect: CGRect(x: 900, y: 400, width: 40, height: 40)
    )
    let occupancy = PieceDetection.occupancy(
        from: [a1, a1WrongType, h8, offBoard],
        quad: quad,
        orientation: .whiteAtBottom
    )
    #expect(occupancy.occupied(ChessSquare(file: 0, rank: 0)))
    #expect(occupancy.occupied(ChessSquare(file: 7, rank: 7)))
    #expect(occupancy.hammingDistance(to: Occupancy()) == 2)
}

@Test func occupancyMapsPaddedWarpBaseThroughRefinedGrid() {
    var points: [CGPoint] = []
    let size: CGFloat = 512
    for row in 0...8 {
        for col in 0...8 {
            let x = CGFloat(col) * (size / 8) + (col == 0 ? -4 : 0)
            let y = CGFloat(row) * (size / 8) + (row == 8 ? 4 : 0)
            points.append(CGPoint(x: x, y: y))
        }
    }
    let grid = RefinedBoardGrid(imageSize: size, points: points)
    let a1 = PieceDetection.Box(
        id: 0,
        piece: .whiteRook,
        confidence: 0.9,
        bufferRect: CGRect(x: 8, y: 448, width: 40, height: 48)
    )
    let h8 = PieceDetection.Box(
        id: 1,
        piece: .blackRook,
        confidence: 0.9,
        bufferRect: CGRect(x: 460, y: 8, width: 40, height: 40)
    )
    let occupancy = PieceDetection.occupancy(
        from: [a1, h8],
        paddedImageSize: 512,
        margin: 0,
        orientation: .whiteAtBottom,
        grid: grid
    )
    #expect(occupancy.occupied(ChessSquare.parse("a1")!))
    #expect(occupancy.occupied(ChessSquare.parse("h8")!))
}

@Test func occupancyMapsPaddedMarginBackToPlayingSquares() {
    let margin: CGFloat = 0.06
    let span = 1 + 2 * margin
    let tightBase = CGPoint(x: 288, y: 512)
    let paddedBase = CGPoint(
        x: (tightBase.x / 512 + margin) / span * 512,
        y: (tightBase.y / 512 + margin) / span * 512
    )
    let e1 = PieceDetection.Box(
        id: 0,
        piece: .whiteKing,
        confidence: 0.9,
        bufferRect: CGRect(x: paddedBase.x - 32, y: paddedBase.y - 32, width: 64, height: 64)
    )
    let occupancy = PieceDetection.occupancy(
        from: [e1],
        paddedImageSize: 512,
        margin: margin,
        orientation: .whiteAtBottom
    )
    #expect(occupancy.occupied(ChessSquare.parse("e1")!))
}

@Test func tightUVMapsPaddedMarginBackToPlayingSurface() {
    let margin: CGFloat = 0.06
    let span = 1 + 2 * margin
    let tightBase = CGPoint(x: 288, y: 512)
    let paddedBase = CGPoint(
        x: (tightBase.x / 512 + margin) / span * 512,
        y: (tightBase.y / 512 + margin) / span * 512
    )
    let e1 = PieceDetection.Box(
        id: 0,
        piece: .whiteKing,
        confidence: 0.9,
        bufferRect: CGRect(x: paddedBase.x - 32, y: paddedBase.y - 32, width: 64, height: 64)
    )
    let uv = PieceDetection.tightUV(of: e1, paddedImageSize: 512, margin: margin)
    #expect(uv != nil)
    #expect(abs((uv?.x ?? -1) - tightBase.x / 512) < 0.002)
    #expect(abs((uv?.y ?? -1) - tightBase.y / 512) < 0.002)
    let occupancy = PieceDetection.occupancy(
        from: [e1],
        paddedImageSize: 512,
        margin: margin,
        orientation: .whiteAtBottom
    )
    #expect(occupancy.occupied(ChessSquare.parse("e1")!))
}
