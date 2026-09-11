import CoreGraphics
import Testing
@testable import ChessCamera

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
        bufferRect: CGRect(x: 720, y: 0, width: 60, height: 50)
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
