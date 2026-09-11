# Chess Camera — Technical Requirements Document

**Companion to:** [PRD.md](PRD.md)
**Stack:** Swift 6, SwiftUI, AVFoundation, Vision, Core ML, ChessKit, OpenCV imgproc only, for grid refine at confirm-start, SwiftData, Swift Testing
**Target:** iOS 18+, physical iPhone

---

## 1. Architecture overview

MVVM with a deep vision pipeline behind a small seam. SwiftUI never talks to Vision or Core ML directly. Chess legality never lives in the camera layer.

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI                               │
│  History  NewGame  Detect  ConfirmStart  Live  Replay  Edit │
├─────────────────────────────────────────────────────────────┤
│              RecordingSessionViewModel (@MainActor)          │
│  phase, digital board, move list, FEN, banners, user edits  │
├───────────────┬─────────────────────────┬───────────────────┤
│ Capture       │ VisionPipeline (actor)  │ GameEngine        │
│ CameraSource  │  detect → warp → grid   │  ChessKit Board   │
│ VideoSource   │  classify / occupancy   │  ChessKit Game    │
│               │  settle                 │  MoveInferrer     │
├───────────────┴─────────────────────────┴───────────────────┤
│ SwiftData GameRecord    Core ML PieceClassifier.mlmodel     │
└─────────────────────────────────────────────────────────────┘
```



### Data flow

```
CMSampleBuffer
    → VisionPipeline.process (off main, ~5–10 Hz)
    → BoardObservation (corners, warped image, occupancy, optional classes)
    → RecordingSessionViewModel
         ├─ confirmingStart: build FEN + orientation
         └─ recording: SettleDetector → MoveInferrer → ChessKit.make
    → UI + SwiftData
```

User edits skip vision: they call `GameEngine.apply(san:)` / `undo()` directly.

---



## 2. Key design decisions


| Decision                                                                      | Rationale                                                                  |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| ChessKit owns rules, FEN, PGN, special moves, checkmate                       | Do not reimplement chess. Focus on camera → state.                         |
| Classify **start** (and promotion / recovery); occupancy + rules after move 0 | 12-class every frame is the 10-day failure mode and duplicates waste-sort. |
| Auto board detect + 4-corner fallback                                         | Auto is the product; fallback is the demo insurance.                       |
| Settle-then-infer, never frame-diff → move                                    | Hands, lifts, and captures change many pixels.                             |
| Unique legal-move match                                                       | Chess constraints resolve visual noise. 0 or >1 matches → do not commit.   |
| Process 5–10 Hz, not 30                                                       | Square crops + Core ML on 64 tiles must stay off the main thread.          |
| Video import uses the same `FrameSource` seam                                 | Repeatable tests without a live board.                                     |
| `@Observable` ViewModel + pipeline `actor`                                    | iOS 17+ observation; isolation for Vision/Core ML.                         |


---



## 3. Module seams

Each module is a deep unit: small interface, large implementation. Tests cross the same seam as callers.

### 3.1 `FrameSource`

```swift
protocol FrameSource: Sendable {
    var frames: AsyncStream<CVPixelBuffer> { get }
    func start() async throws
    func stop() async
}
```

Adapters: `LiveCameraSource` (AVFoundation), `AssetVideoSource` (AVAssetReader).

### 3.2 `BoardLocalizer`

```swift
struct Quadrilateral: Equatable, Sendable {
    var topLeft, topRight, bottomRight, bottomLeft: CGPoint // image space, pixels
}

protocol BoardLocalizer: Sendable {
    func detect(in buffer: CVPixelBuffer) async -> Quadrilateral?
}
```

- Primary: Vision `VNDetectRectanglesRequest` (minimum aspect ratio ~0.8–1.25, maximum 1 rectangle that looks like a board). Optional follow-up: line grouping if rectangle quality is poor.
- Fallback: user-supplied quad from the 4-corner UI, stored on the session.
- Once a stable quad is accepted, **track** it (`VNTrackObjectRequest` or lock the quad if the phone is mounted). Do not re-detect from scratch every frame unless tracking is lost.



### 3.3 `BoardWarper`

```swift
struct WarpedBoard: Sendable {
    var squareImage: CGImage           // square, e.g. 512×512 or 640×640
    var quad: Quadrilateral
}

enum BoardWarper {
    static func warp(_ buffer: CVPixelBuffer, quad: Quadrilateral, size: Int) -> WarpedBoard?
}
```

Implementation: Core Image `CIPerspectiveCorrection` or a 3×3 homography applied with `vImage` / Metal. Output is axis-aligned; rank 8 is the top of the image **in camera space** until orientation is applied.

### 3.4 `GridSampler`

```swift
struct SquareCrop: Sendable, Identifiable {
    var square: ChessSquare          // a1...h8 after orientation
    var image: CGImage               // one tile, e.g. 64×64
}

enum GridSampler {
    static func crops(from warped: CGImage, files: 8, ranks: 8) -> [SquareCrop] // 64 items
}
```

Inset each tile by ~10–15% to avoid neighboring pieces and gutter lines. Orientation (`BoardOrientation`) maps grid index `(file, rankInImage)` → algebraic square.

### 3.5 `PieceClassifier`

```swift
enum PieceClass: String, CaseIterable, Sendable {
    case empty
    case whitePawn, whiteKnight, whiteBishop, whiteRook, whiteQueen, whiteKing
    case blackPawn, blackKnight, blackBishop, blackRook, blackQueen, blackKing
}

protocol PieceClassifier: Sendable {
    func classify(_ crop: SquareCrop) async -> (PieceClass, confidence: Float)
}
```

Core ML image classifier on square crops. Threshold: treat as `empty` if empty-class confidence is high **or** occupancy heuristic says empty (see §6). Adapter `CoreMLPieceClassifier`; tests use a fake.

### 3.6 `OccupancyEstimator`

```swift
struct Occupancy: Equatable, Sendable {
    var bits: UInt64                 // bit 0 = a1, bit 7 = h1, bit 56 = a8
    func occupied(_ square: ChessSquare) -> Bool
}

protocol OccupancyEstimator: Sendable {
    func occupancy(crops: [SquareCrop], classes: [PieceClass]?) -> Occupancy
}
```

Combine (a) classifier `!= .empty` and (b) a cheap empty-square score (variance / difference vs a per-square empty baseline captured at confirm-start). After move 0, occupancy is the primary visual signal.

### 3.7 `SettleDetector`

```swift
struct SettleConfig: Sendable {
    var stableDuration: Duration     // default .milliseconds(600)
    var maxHammingJitter: Int        // default 0
}

enum BoardMotion: Equatable, Sendable {
    case stable(Occupancy)
    case disturbed(since: Occupancy)
}

struct SettleDetector: Sendable {
    var config: SettleConfig
    mutating func ingest(_ occupancy: Occupancy, at time: ContinuousClock.Instant) -> BoardMotion
}
```

State machine: `stable` → on Hamming distance > 0 become `disturbed` → when occupancy equals the last disturbed snapshot for `stableDuration`, emit `stable` again.

### 3.8 `MoveInferrer`

```swift
struct VisualDelta: Equatable, Sendable {
    var previous: Occupancy
    var current: Occupancy
    var observedClasses: [ChessSquare: PieceClass]  // optional, used for promotion
}

enum InferenceResult: Equatable, Sendable {
    case none
    case unique(Move)                // ChessKit Move
    case ambiguous([Move])
    case illegal                     // occupancy changed but no legal move matches
}

enum MoveInferrer {
    static func infer(delta: VisualDelta, board: Board) -> InferenceResult
}
```

Algorithm:

1. If `previous == current`, return `.none`.
2. Ask ChessKit for every legal move in `board` (iterate pieces / `legalMoves(forPieceAt:)`).
3. For each legal move, simulate on a copy: `trial.move(pieceAt:to:)` (ChessKit handles castling, en passant, and default promotion). Compare resulting occupancy (and king/rook squares for castling; captured pawn square for en passant) to `current`.
4. Promotion: if several promotion pieces match occupancy, pick the class on the destination square from `observedClasses`; if missing, default to queen and let the user edit.
5. 1 match → `.unique`; 0 → `.illegal`; >1 → `.ambiguous`.

Never commit `.illegal` or `.ambiguous`. Surface a banner; user edits.

### 3.9 `GameEngine`

Thin wrapper around ChessKit so the rest of the app does not scatter `Board` / `Game` calls.

```swift
@Observable
final class GameEngine {
    private(set) var board: Board
    private(set) var game: Game
    var fen: String { board.position.fen }
    var pgn: String { game.pgn }
    var state: Board.State { board.state }   // .active, .check, .checkmate(color:), etc.

    func apply(move: Move) throws
    func apply(san: String) throws           // Game.make(move:index:)
    func undo() throws
    func replaceMove(at index: MoveTree.Index, with san: String) throws
}
```

ChessKit (from current docs):

- `Board()`, `board.move(pieceAt:to:)`, `board.legalMoves(forPieceAt:)`, `board.canMove(pieceAt:to:)`, `board.state`
- `Position(fen:)`, `position.fen`
- `Game(pgn:)`, `game.pgn`, `game.make(move:index:)` with SAN, `Game.moves` as `MoveTree`, `Game.positions`

Pin a specific ChessKit version in the Xcode project when adding the package. If a property name differs (`position.fen` vs `FENParser`), adapt only inside `GameEngine`.

---



## 4. Domain types

```swift
struct ChessSquare: Hashable, Sendable, Codable {
    var file: Int   // 0...7 = a...h
    var rank: Int   // 0...7 = 1...8
    var algebraic: String { "\(fileName)\(rank + 1)" }
}

enum BoardOrientation: Sendable {
    case whiteAtBottom   // a1 image-bottom-left after warp
    case whiteAtLeft     // a1 image-top-left (camera on h-file)
    case whiteAtTop      // a1 image-top-right
    case whiteAtRight    // a1 image-bottom-right (camera on a-file)
}

struct BoardObservation: Sendable {
    var timestamp: ContinuousClock.Instant
    var quad: Quadrilateral
    var occupancy: Occupancy
    var classes: [ChessSquare: PieceClass]
}

enum SessionPhase: Equatable {
    case idle
    case importingVideo
    case detectingBoard
    case calibratingCorners
    case confirmingStart
    case recording
    case disturbed
    case awaitingEdit          // illegal / ambiguous delta
    case gameOver
    case replay
}
```

SwiftData:

```swift
@Model
final class GameRecord {
    var createdAt: Date
    var pgn: String
    var finalFen: String
    var title: String          // default "Game · MMM d"
}
```

Replay is derived from PGN via `Game(pgn:)`; do not store a second move list unless profiling shows parse cost.

---



## 5. Board detection and orientation



### Detection

1. Downscale the camera frame (longest side ~1280) for Vision.
2. `VNDetectRectanglesRequest`: largest quad that is roughly square and occupies a meaningful fraction of the frame (e.g. ≥ 35% of min(width,height)).
3. Score by: squareness after hypothesizing a square, edge strength, and “grid-likeness” (optional: detect interior lines with `VNDetectContoursRequest` / Hough — only if rectangles are flaky).
4. If no candidate for ~2 seconds, prompt 4-corner fallback.
5. User can always open “Adjust corners.”



### Homography

Map the four corners to `(0,0), (S,0), (S,S), (0,S)`. Warp. The warped image is **camera-up**: which physical rank is at the top is unknown until orientation.

### Orientation from pieces (FR-8)

The warped image stays **camera-up**. `BoardOrientation` maps grid indices to algebraic squares so the phone can sit on any of the four sides of the table (`whiteAtBottom` / `whiteAtLeft` / `whiteAtTop` / `whiteAtRight`). Rotate cycles 90° clockwise; it remaps FEN without re-classifying.

After classifying all 64 squares at confirm-start:

1. Locate the white king in image space (via the classify-time orientation). Pick the image edge it is closest to: bottom → `whiteAtBottom`, top → `whiteAtTop`, left → `whiteAtLeft`, right → `whiteAtRight`.
2. Remap classified squares from the classify-time orientation to the inferred one, then build FEN.
3. User can **Rotate** on Board Studio and Confirm Start until `a1` is White’s queenside rook square in the **standard start**.

If the classified FEN is not the standard starting position, show it on the confirm screen. Demo path: user rearranges the physical pieces and taps Recapture. Mid-game start is a stretch (classifier + FEN), not the success bar.

---



## 6. Piece model (your set only)



### Training

1. Photograph the demo set: empty board + each piece type on light and dark squares, several files/ranks, demo lighting, camera angle similar to the mount.
2. Crop to squares (the app’s debug exporter should dump 64 crops from a live frame — build this on day 5).
3. Labels: 13 classes (`empty` + 12 pieces).
4. Train an image classifier in **Create ML** (Xcode) targeting iOS. Keep the model small (MobileNetV2 / Create ML default is fine).
5. Bundle `PieceClassifier.mlmodel` in the app target.

Do not scrape a public dataset as the primary model. Transfer learning from a public set is allowed only if Create ML on your photos is insufficient — still fine-tune on your set.

### Runtime policy


| Moment        | Classifier               | Occupancy  | ChessKit                                |
| ------------- | ------------------------ | ---------- | --------------------------------------- |
| Confirm start | Required                 | Supporting | Build FEN; must be legal                |
| During game   | Off by default           | Required   | Infer move                              |
| Promotion     | Destination square only  | Required   | Disambiguate piece                      |
| Recovery      | User-triggered recapture | Required   | Compare to FEN; if mismatch, offer edit |


Empty-square baseline: when the user confirms start, store a downsampled fingerprint per square that the classifier called `empty`. Later occupancy can use distance-to-baseline to survive lighting drift better than a global threshold.

---



## 7. Settle and move commit

```
lastCommittedOccupancy = occupancy(at: confirmed start)
loop:
  obs = pipeline.observation
  motion = settle.ingest(obs.occupancy)
  if phase == recording && motion is disturbed:
      phase = disturbed          // HUD: “Waiting for the board…”
  if phase == disturbed && motion is stable(occ):
      switch MoveInferrer.infer(previous: lastCommitted, current: occ, board):
        case unique(move):
            engine.apply(move)
            lastCommitted = occ
            phase = recording
        case none:
            phase = recording    // jitter
        case ambiguous, illegal:
            phase = awaitingEdit // banner + tap to fix
```



### Special moves (how occupancy looks)


| Event      | Occupancy Hamming (typical)       | Extra visual cue                                  |
| ---------- | --------------------------------- | ------------------------------------------------- |
| Quiet move | 2                                 | —                                                 |
| Capture    | 2 (from empty, to still occupied) | Destination class may change color                |
| Castling   | 4                                 | Two pieces moved                                  |
| En passant | 3                                 | Captured pawn square emptied, not the destination |
| Promotion  | 2                                 | Destination class ≠ pawn                          |


ChessKit simulation is the matcher. Occupancy Hamming is only a hint for logging.

### Timing

Default settle **600 ms**. Expose in a debug settings pane (0.3–1.5 s) for demo day. Too short: mid-move commits. Too long: feels laggy.

---



## 8. Capture and performance

- Session: `AVCaptureSession` preset `.hd1920x1080` or `.hd1280x720`. Portrait and landscape both work; use video orientation from device.
- Deliver frames on a background queue; convert to `CVPixelBuffer` and send into the actor.
- **Throttle:** process at most 10 Hz. Drop frames if `VisionPipeline` is busy.
- Core ML: if classifying 64 squares at start, do it once (or a short burst of 3 frames and majority vote), not continuously.
- During recording, skip Core ML except promotion / debug overlay.
- UI overlay (quad, last move) updates on main actor from the latest observation; never wait for inference in `body`.

Video import: `AVAssetReader` → same `AsyncStream`. Clock timestamps from the asset for settle durations (use video time, not wall clock).

---



## 9. Persistence and export

- On End Game or checkmate/stalemate confirmed: insert `GameRecord`.
- Share: `UIActivityViewController` with PGN UTF-8 as a `.pgn` file (`text/plain`).
- Copy FEN / PGN to clipboard.
- Delete from History with swipe; confirm destructive delete.

No iCloud. No backend.

---



## 10. Testing strategy

Vision and Core ML are hard to unit-test. **Pure logic must be tested.** Camera and Vision are covered by video fixtures + a debug screen.


| Layer                                              | How                                                                                                       |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `ChessSquare`, occupancy bits, orientation mapping | Swift Testing, synthetic                                                                                  |
| `SettleDetector`                                   | Fake occupancy timelines                                                                                  |
| `MoveInferrer`                                     | ChessKit boards + constructed deltas for quiet, capture, O-O, O-O-O, e.p., promotion, illegal, ambiguous  |
| `GameEngine` undo / SAN / PGN round-trip           | Swift Testing                                                                                             |
| `GridSampler` index math                           | Known warped size → a1 pixel center                                                                       |
| Classifier                                         | Manual on demo set; optional accuracy script on a held-out crop folder                                    |
| Full pipeline                                      | 2–3 short recorded videos in `Fixtures/` (not huge binaries in git if avoidable — document how to record) |


Do not snapshot entire camera frames in unit tests.

---



## 11. Failure modes


| Symptom           | Likely cause                       | Handling                                                           |
| ----------------- | ---------------------------------- | ------------------------------------------------------------------ |
| Quad jumps        | Bad rectangle / table edge         | Tracking lock + “Adjust corners”                                   |
| Start FEN wrong   | Classifier / lighting              | Confirm screen: tap squares to cycle piece, Recapture, Rotate      |
| Move not detected | Settle too long / occupancy missed | Debug overlay of occupancy; lower settle; recapture empty baseline |
| Extra move        | Hands still; settle too short      | Disturbed HUD; raise settle                                        |
| Castling missed   | Inferrer occupancy mismatch        | Fixture test; ensure simulated occupancy includes rook             |
| Desync mid-game   | Missed move                        | Undo / edit last ply; optional recapture stretch                   |


---



## 12. Project structure (target)

```
ChessCamera/
  App/ChessCameraApp.swift
  App/AppContainer.swift
  Capture/FrameSource.swift
  Capture/LiveCameraSource.swift
  Capture/AssetVideoSource.swift
  Vision/BoardLocalizer.swift
  Vision/BoardWarper.swift
  Vision/GridSampler.swift
  Vision/OccupancyEstimator.swift
  Vision/VisionPipeline.swift
  ML/PieceClassifier.swift
  ML/PieceClassifier.mlmodel
  Chess/ChessSquare.swift
  Chess/Occupancy.swift
  Chess/SettleDetector.swift
  Chess/MoveInferrer.swift
  Chess/GameEngine.swift
  Session/RecordingSessionViewModel.swift
  Session/SessionPhase.swift
  Persistence/GameRecord.swift
  Features/History/HistoryView.swift
  Features/Live/LiveRecordingView.swift
  Features/Live/CornerCalibrationView.swift
  Features/Live/ConfirmStartView.swift
  Features/Replay/ReplayView.swift
  Features/Replay/EditMoveSheet.swift
  UI/Theme.swift
  UI/DigitalBoardView.swift
  UI/MoveListView.swift
ChessCameraTests/
  OccupancyTests.swift
  SettleDetectorTests.swift
  MoveInferrerTests.swift
  GridSamplerTests.swift
  GameEngineTests.swift
```

(Keep `DigitalBoardView` under `UI/` — single digital board used in live, confirm, and replay.)

---



## 13. Third-party packages


| Package                                                                       | Purpose                                          |
| ----------------------------------------------------------------------------- | ------------------------------------------------ |
| [chesskit-app/chesskit-swift](https://github.com/chesskit-app/chesskit-swift) | Legal moves, special moves, FEN, PGN, game state |
| [yeatse/opencv-spm](https://github.com/yeatse/opencv-spm) | OpenCV imgproc only, for grid refine at confirm-start |

No Stockfish. No iCloud.

---



## 14. Differentiation from waste-sort

Waste-sort: camera → object class → category.

Chess Camera: camera → **geometry (homography, 64-square map)** → **temporal settle** → **constraint solve against legal moves** → PGN.

The Core ML classifier is a bootstrap for move 0 (and promotion), not the product.