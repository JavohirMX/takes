# Chess Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iPhone prototype that watches a physical board, confirms a classified standard start, records a full game via occupancy settle + ChessKit inference, and saves replayable PGN/FEN locally.

**Architecture:** SwiftUI talks only to `RecordingSessionViewModel`. A `VisionPipeline` actor turns frames into occupancy. `MoveInferrer` + `GameEngine` (ChessKit) are pure and fully unit-tested. Live camera and imported video share `FrameSource`.

**Tech Stack:** Swift 6, SwiftUI, iOS 18+, AVFoundation, Vision, Core ML, ChessKit (`chesskit-app/chesskit-swift`), SwiftData, Swift Testing.

Read first: [docs/PRD.md](PRD.md), [docs/TRD.md](TRD.md), [docs/UI_UX.md](UI_UX.md), [docs/APP_FLOW.md](APP_FLOW.md).

## Global Constraints

- iOS 18+, Swift 6, SwiftUI lifecycle (`@main App`), physical iPhone for camera.
- Apple Vision + Core ML only. No OpenCV. No paid AI APIs. No Stockfish. No iCloud.
- Chess legality, FEN, PGN, special moves, checkmate: ChessKit only, wrapped in `GameEngine`.
- Demo path: one chess set, standard start, still camera, full board visible, 600 ms settle.
- After move 0, game state is source of truth; classifier is for start, promotion, recovery.
- Auto-accept moves; user edits/undos later. Only last ply is editable in MVP.
- Dark-only UI tokens from [UI_UX.md](UI_UX.md). SF Symbols, no emoji icons.
- Swift Testing (`import Testing`), not XCTest, for new tests.
- Bundle name / display name: Chess Camera. Module name: `ChessCamera`.

---

## File structure (create as tasks land)

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
  ML/PieceClass.swift
  ML/PieceClassifier.swift
  Chess/ChessSquare.swift
  Chess/Occupancy.swift
  Chess/BoardOrientation.swift
  Chess/SettleDetector.swift
  Chess/MoveInferrer.swift
  Chess/GameEngine.swift
  Session/SessionPhase.swift
  Session/RecordingSessionViewModel.swift
  Persistence/GameRecord.swift
  Features/History/HistoryView.swift
  Features/Setup/SetupPrimerView.swift
  Features/Setup/CameraPermissionView.swift
  Features/Live/LiveRecordingView.swift
  Features/Live/BoardDetectionView.swift
  Features/Live/CornerCalibrationView.swift
  Features/Live/ConfirmStartView.swift
  Features/Replay/ReplayView.swift
  Features/Replay/GameOverView.swift
  Features/Replay/EditMoveSheet.swift
  UI/Theme.swift
  UI/DigitalBoardView.swift
  UI/MoveListView.swift
  UI/FenBar.swift
  UI/CameraPreview.swift
  UI/BoardQuadOverlay.swift
  UI/StatusBanner.swift
  UI/PrimaryButton.swift
ChessCameraTests/
  ChessSquareTests.swift
  OccupancyTests.swift
  GridSamplerTests.swift
  SettleDetectorTests.swift
  MoveInferrerTests.swift
  GameEngineTests.swift
```

---

### Task 1: Xcode app, theme, History shell

**Files:**
- Create: `ChessCamera/App/ChessCameraApp.swift`
- Create: `ChessCamera/UI/Theme.swift`
- Create: `ChessCamera/Features/History/HistoryView.swift`
- Create: `ChessCamera/UI/PrimaryButton.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `Theme` color tokens; `HistoryView` empty state; app boots to History

- [ ] **Step 1: Create the Xcode project**

Xcode → App → product name `ChessCamera`, interface SwiftUI, language Swift, minimum iOS 18.0. Include a unit test target `ChessCameraTests` using Swift Testing. Enable Swift 6 language mode.

Info.plist keys (or target Info tab):

- `NSCameraUsageDescription` = `Chess Camera watches the board to record your game.`
- `NSPhotoLibraryUsageDescription` = `Import a recorded video to test the same pipeline.`

- [ ] **Step 2: Add `Theme.swift`**

```swift
import SwiftUI

enum Theme {
    static let background = Color(red: 0.06, green: 0.09, blue: 0.16)      // #0F172A
    static let surface = Color(red: 0.12, green: 0.16, blue: 0.23)         // #1E293B
    static let surfaceMuted = Color(red: 0.15, green: 0.18, blue: 0.26)    // #272F42
    static let border = Color(red: 0.28, green: 0.33, blue: 0.41)          // #475569
    static let textPrimary = Color(red: 0.97, green: 0.98, blue: 0.99)     // #F8FAFC
    static let textSecondary = Color(red: 0.58, green: 0.64, blue: 0.72)   // #94A3B8
    static let accent = Color(red: 0.13, green: 0.77, blue: 0.37)          // #22C55E
    static let onAccent = Color(red: 0.02, green: 0.18, blue: 0.09)        // #052E16
    static let caution = Color(red: 0.96, green: 0.62, blue: 0.04)         // #F59E0B
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)          // #EF4444
    static let boardLight = Color(red: 0.89, green: 0.91, blue: 0.94)      // #E2E8F0
    static let boardDark = Color(red: 0.28, green: 0.33, blue: 0.41)       // #475569
}
```

- [ ] **Step 3: Empty History + `PrimaryButton` + `#Preview`**

Root `NavigationStack` with title Chess Camera, empty copy from UI_UX, one **New Game** button (can be a no-op until Task 7). Dark `Theme.background`.

- [ ] **Step 4: Run on simulator**

Expected: dark History empty state, Dynamic Type does not clip the CTA (44 pt min height).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: bootstrap Chess Camera app shell and dark theme

EOF
)"
```

---

### Task 2: Squares and occupancy

**Files:**
- Create: `ChessCamera/Chess/ChessSquare.swift`
- Create: `ChessCamera/Chess/Occupancy.swift`
- Create: `ChessCamera/Chess/BoardOrientation.swift`
- Test: `ChessCameraTests/ChessSquareTests.swift`
- Test: `ChessCameraTests/OccupancyTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `ChessSquare` (a1–h8), `Occupancy` (`UInt64`, bit 0 = a1, bit 7 = h1, bit 56 = a8), `BoardOrientation`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import ChessCamera

@Test func algebraicA1() {
    #expect(ChessSquare(file: 0, rank: 0).algebraic == "a1")
}

@Test func algebraicH8() {
    #expect(ChessSquare(file: 7, rank: 7).algebraic == "h8")
}

@Test func occupancyBitA1() {
    var occ = Occupancy()
    occ.set(ChessSquare(file: 0, rank: 0), occupied: true)
    #expect(occ.occupied(ChessSquare(file: 0, rank: 0)))
    #expect(occ.bits == 1)
}

@Test func occupancyHammingQuietMove() {
    var a = Occupancy.fullStandardPawnsAndPieces() // helper: start position occupancy
    var b = a
    b.set(ChessSquare(file: 4, rank: 1), occupied: false) // e2
    b.set(ChessSquare(file: 4, rank: 3), occupied: true)  // e4
    #expect(a.hammingDistance(to: b) == 2)
}
```

- [ ] **Step 2: Run tests — expect FAIL** (types missing)

- [ ] **Step 3: Implement `ChessSquare`, `Occupancy`, `BoardOrientation`**

```swift
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

struct Occupancy: Equatable, Sendable {
    var bits: UInt64 = 0

    func occupied(_ square: ChessSquare) -> Bool {
        (bits & (1 << square.bitIndex)) != 0
    }

    mutating func set(_ square: ChessSquare, occupied: Bool) {
        let mask: UInt64 = 1 << square.bitIndex
        if occupied { bits |= mask } else { bits &= ~mask }
    }

    func hammingDistance(to other: Occupancy) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }
}

enum BoardOrientation: Sendable, Equatable {
    case whiteAtBottom
    case whiteAtTop
}
```

Add `Occupancy.standardStart()` setting bits for ranks 1,2,7,8.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit** `feat: add chess square and occupancy bitboard`

---

### Task 3: GridSampler mapping

**Files:**
- Create: `ChessCamera/Vision/GridSampler.swift`
- Test: `ChessCameraTests/GridSamplerTests.swift`

**Interfaces:**
- Consumes: `ChessSquare`, `BoardOrientation`
- Produces: `GridSampler.square(fileIndex:rankFromBottom:orientation:)` and crop rects in a square image

- [ ] **Step 1: Failing tests**

For a 512×512 warped image, inset 0, `whiteAtBottom`: file 0 rank 0 (a1) center is near bottom-left.

```swift
@Test func a1IsBottomLeftWhenWhiteAtBottom() {
    let r = GridSampler.rect(
        fileIndex: 0,
        rankFromImageTop: 7,
        imageSize: 512,
        inset: 0
    )
    #expect(r.midX == 32)
    #expect(r.midY == 512 - 32)
}

@Test func orientationMapsImageRankToA1() {
    let sq = GridSampler.square(
        fileIndex: 0,
        rankFromImageTop: 7,
        orientation: .whiteAtBottom
    )
    #expect(sq.algebraic == "a1")
}
```

If `whiteAtTop`, image-top rank is rank 1 and files are mirrored (h-file on the left). Encode that explicitly in `GridSampler` and test `a1` accordingly.

- [ ] **Step 2: Implement `GridSampler`** (pure CGRect math, no Vision)

- [ ] **Step 3: Tests PASS, commit** `feat: map warped board pixels to algebraic squares`

---

### Task 4: SettleDetector

**Files:**
- Create: `ChessCamera/Chess/SettleDetector.swift`
- Test: `ChessCameraTests/SettleDetectorTests.swift`

**Interfaces:**
- Consumes: `Occupancy`
- Produces: `BoardMotion.stable` / `.disturbed`

- [ ] **Step 1: Failing tests using a fake clock**

Inject `ContinuousClock.Instant` — do not sleep.

```swift
@Test func becomesDisturbedOnOccupancyChange() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock.Instant.now
    let empty = Occupancy()
    var e4 = Occupancy()
    e4.set(ChessSquare.parse("e4")!, occupied: true)
    _ = d.ingest(empty, at: t0)
    let m = d.ingest(e4, at: t0)
    #expect(m == .disturbed(since: e4))
}

@Test func returnsStableAfterDurationWithSameBits() {
    var d = SettleDetector(config: .init(stableDuration: .milliseconds(600)))
    let t0 = ContinuousClock.Instant.now
    var occ = Occupancy()
    occ.set(ChessSquare.parse("e4")!, occupied: true)
    _ = d.ingest(occ, at: t0)
    _ = d.ingest(occ, at: t0.advanced(by: .milliseconds(200)))
    let m = d.ingest(occ, at: t0.advanced(by: .milliseconds(600)))
    #expect(m == .stable(occ))
}
```

- [ ] **Step 2: Implement the state machine from TRD §7**

- [ ] **Step 3: Tests PASS, commit** `feat: settle detector waits for a still board`

---

### Task 5: ChessKit GameEngine

**Files:**
- Create: `ChessCamera/Chess/GameEngine.swift`
- Test: `ChessCameraTests/GameEngineTests.swift`

**Interfaces:**
- Consumes: ChessKit
- Produces: `apply(san:)`, `undo()`, `fen`, `pgn`, `state`, occupancy snapshot from position

- [ ] **Step 1: Add SPM package** `https://github.com/chesskit-app/chesskit-swift` (up to next major; pin the resolved version in `Package.resolved` / pbxproj)

- [ ] **Step 2: Failing tests**

```swift
@Test func e4UpdatesFenAndPgn() throws {
    let engine = GameEngine()
    try engine.apply(san: "e4")
    #expect(engine.pgn.contains("e4"))
    #expect(engine.fen.contains("4P3")) // pawn on e4 in FEN piece placement
}

@Test func undoRestoresStart() throws {
    let engine = GameEngine()
    let start = engine.fen
    try engine.apply(san: "e4")
    try engine.undo()
    #expect(engine.fen == start)
}

@Test func castlingIsLegalFromStartAfterClearing() throws {
    // Set up a FEN where White can castle short, apply O-O, expect king g1 rook f1
}
```

- [ ] **Step 3: Wrap ChessKit**

Use `Board()`, `Game`, `Move(san:in:)`, `game.make(move:index:)`, `game.pgn`, `position.fen`, `board.state`. If a symbol name differs in the pinned version, change **only** `GameEngine`.

Add `GameEngine.occupancy() -> Occupancy` by enumerating pieces on `board.position`.

- [ ] **Step 4: Tests PASS, commit** `feat: wrap ChessKit for FEN PGN undo and occupancy`

---

### Task 6: MoveInferrer (core algorithm)

**Files:**
- Create: `ChessCamera/Chess/MoveInferrer.swift`
- Create: `ChessCamera/ML/PieceClass.swift`
- Test: `ChessCameraTests/MoveInferrerTests.swift`

**Interfaces:**
- Consumes: `Occupancy`, `GameEngine` / `Board`, optional `[ChessSquare: PieceClass]`
- Produces: `InferenceResult`

- [ ] **Step 1: Write the fixture table as tests** (all must fail first)

| Name | Setup | Occupancy delta | Expected SAN |
|---|---|---|---|
| quiet | start | e2 empty, e4 occupied | `e4` |
| capture | Italian-like FEN | bishop takes knight | `Bxc6` or the SAN ChessKit emits |
| castleShort | FEN with O-O available | king+rook occupancy | `O-O` |
| castleLong | FEN with O-O-O | king+rook | `O-O-O` |
| enPassant | FEN with e.p. legal | 3-square occupancy | SAN from ChessKit |
| promotion | pawn on 7th | dest occupied, pawn gone | `e8=Q` if class queen / default queen |
| none | identical occupancy | — | `.none` |
| illegal | random 4 bits flipped | — | `.illegal` |

```swift
@Test func infersE4FromStart() {
    let engine = GameEngine()
    let before = engine.occupancy()
    var after = before
    after.set(ChessSquare.parse("e2")!, occupied: false)
    after.set(ChessSquare.parse("e4")!, occupied: true)
    let result = MoveInferrer.infer(
        delta: VisualDelta(previous: before, current: after, observedClasses: [:]),
        board: engine.board
    )
    #expect(result.san == "e4") // add helper on InferenceResult for tests
}
```

Repeat for each row. For SAN, compare against ChessKit’s own `Move.san` after applying on a trial board so notation stays canonical.

- [ ] **Step 2: Implement `MoveInferrer.infer` as specified in TRD §3.8**

Enumerate legal moves, simulate, compare occupancy (and promotion class).

- [ ] **Step 3: All fixture tests PASS**

- [ ] **Step 4: Commit** `feat: infer legal chess moves from occupancy deltas`

This task is the technical heart of the project. Do not proceed to live UI until the fixture table is green.

---

### Task 7: FrameSource + live camera preview

**Files:**
- Create: `ChessCamera/Capture/FrameSource.swift`
- Create: `ChessCamera/Capture/LiveCameraSource.swift`
- Create: `ChessCamera/UI/CameraPreview.swift`
- Create: `ChessCamera/Features/Live/BoardDetectionView.swift` (preview only)
- Create: `ChessCamera/Features/Setup/CameraPermissionView.swift`

**Interfaces:**
- Consumes: AVFoundation
- Produces: `AsyncStream<CVPixelBuffer>`; SwiftUI preview with `.resizeAspect`

- [ ] **Step 1: `FrameSource` protocol** (TRD §3.1)

- [ ] **Step 2: `LiveCameraSource`** — `AVCaptureSession`, 1280×720, video data output on a serial queue, yield buffers. `stop()` tears down.

- [ ] **Step 3: `CameraPreview` UIViewRepresentable** wrapping `AVCaptureVideoPreviewLayer`, gravity `.resizeAspect`. Document a helper that maps view points → buffer pixels **including letterbox**. Unit-test the math function `VideoMapping.viewToBuffer(point:viewSize:bufferSize:)` with a known 16:9 buffer in a 9:16 view.

- [ ] **Step 4: Permission primer** if `AVCaptureDevice.authorizationStatus != .authorized`

- [ ] **Step 5: Wire History New Game → camera fullScreenCover** (no detection yet)

- [ ] **Step 6: Run on a physical iPhone** — expect live preview, session stops on dismiss

- [ ] **Step 7: Commit** `feat: live camera preview with aspect-correct mapping`

---

### Task 8: Board localize + warp

**Files:**
- Create: `ChessCamera/Vision/BoardLocalizer.swift`
- Create: `ChessCamera/Vision/BoardWarper.swift`
- Create: `ChessCamera/UI/BoardQuadOverlay.swift`

**Interfaces:**
- Consumes: `CVPixelBuffer`, `Quadrilateral`
- Produces: detected quad; square `CGImage`

- [ ] **Step 1: `VNDetectRectanglesRequest` localizer** with squareness + min size filters (TRD §5)

- [ ] **Step 2: Overlay the quad on `CameraPreview` using `VideoMapping`**

- [ ] **Step 3: `BoardWarper` via `CIPerspectiveCorrection`** to 512×512; debug: show warped image in a corner thumbnail

- [ ] **Step 4: Physical check** — board visible, quad roughly on the four corners; warp looks like a square board

- [ ] **Step 5: Commit** `feat: detect board rectangle and warp to a square`

---

### Task 9: Four-corner fallback

**Files:**
- Create: `ChessCamera/Features/Live/CornerCalibrationView.swift`
- Modify: detection flow to offer Adjust corners after ~2 s and always as secondary

**Interfaces:**
- Consumes: `Quadrilateral`
- Produces: user-confirmed quad for the session

- [ ] **Step 1: Four draggable handles, 44 pt hit targets, clamped to the video rect**

- [ ] **Step 2: Looks good / Use these corners → lock quad** (tracking optional: reuse last quad if phone is still)

- [ ] **Step 3: Device test** — auto-detect fail path still reaches a usable warp

- [ ] **Step 4: Commit** `feat: manual four-corner board calibration`

---

### Task 10: Piece classifier training + runtime

**Files:**
- Create: `ChessCamera/ML/PieceClass.swift` (if not already)
- Create: `ChessCamera/ML/PieceClassifier.swift`
- Create: `ChessCamera/Vision/OccupancyEstimator.swift`
- Add: `ChessCamera/ML/PieceClassifier.mlmodel` (trained artifact)
- Optional debug: export 64 crops from a live warped frame to Files / share

**Interfaces:**
- Consumes: `SquareCrop`
- Produces: `(PieceClass, confidence)`; occupancy from classes + empty heuristic

- [ ] **Step 1: Debug crop dump** from warped 512×512 using `GridSampler` (orientation assumed `whiteAtBottom` until confirm)

- [ ] **Step 2: Photograph the demo set** (empty + 12 piece types on light/dark, demo lighting). Label 13 classes.

- [ ] **Step 3: Train Create ML image classifier, export Core ML, bundle in the target**

- [ ] **Step 4: `CoreMLPieceClassifier` + `OccupancyEstimator`**

Empty if class is `.empty` OR confidence for empty/occupancy heuristic says empty.

- [ ] **Step 5: Sanity check** — standard start: ranks 1–2 White, 7–8 Black, 3–6 empty, ≥ 60/64 correct. If not, more photos, do not “fix” with a public dataset as the primary model.

- [ ] **Step 6: Commit** `feat: on-device piece classifier trained on the demo set`

Do not commit thousands of training photos if they are huge; keep the `.mlmodel` and a short `docs/training-notes.md` with how to reproduce.

---

### Task 11: Confirm starting position + orientation

**Files:**
- Create: `ChessCamera/Features/Live/ConfirmStartView.swift`
- Modify: `RecordingSessionViewModel` (may start here as a stub)

**Interfaces:**
- Consumes: 64 `PieceClass`, `GridSampler`, ChessKit `Position(fen:)`
- Produces: legal FEN, `BoardOrientation`, **Flip**, **Recapture**, **Start recording** enabled only if FEN legal

- [ ] **Step 1: Build FEN piece placement from classes** (side to move `w`, castling `KQkq`, ep `-`, clocks `0 1` for standard start)

- [ ] **Step 2: Infer orientation from White king rank** (TRD §5); Flip toggles and remaps files/ranks

- [ ] **Step 3: UI from UI_UX §6.5** — digital board, banners, Recapture

- [ ] **Step 4: Device test** — standard start shows the check copy; Flip swaps the digital board

- [ ] **Step 5: Commit** `feat: confirm classified start and board orientation`

---

### Task 12: VisionPipeline + session ViewModel

**Files:**
- Create: `ChessCamera/Session/SessionPhase.swift`
- Create: `ChessCamera/Session/RecordingSessionViewModel.swift`
- Create: `ChessCamera/Vision/VisionPipeline.swift`

**Interfaces:**
- Consumes: `FrameSource`, localizer, warper, occupancy, settle, inferrer, `GameEngine`
- Produces: `phase`, `lastSAN`, `fen`, `pgn`, banners; commits unique moves only

- [ ] **Step 1: Implement the loop in TRD §7 and APP_FLOW phase machine**

Throttle 10 Hz. No Core ML during recording except promotion (destination square).

- [ ] **Step 2: Unit-test the ViewModel with a fake `FrameSource` that yields nothing and a fake occupancy injector** (if that is awkward, test a pure `SessionReducer` that maps `(phase, BoardMotion, InferenceResult) → phase` — prefer a reducer so tests stay off the actor).

```swift
struct SessionReducer {
    static func next(
        phase: SessionPhase,
        motion: BoardMotion,
        inference: InferenceResult
    ) -> SessionPhase { /* matching APP_FLOW */ }
}
```

Test: recording + disturbed occupancy → `.disturbed`; disturbed + unique → `.recording`; disturbed + illegal → `.awaitingEdit`.

- [ ] **Step 3: Device: play `e4` physically, expect digital e2-e4 after ~600 ms**

- [ ] **Step 4: Commit** `feat: record moves from settled occupancy via ChessKit`

---

### Task 13: Adaptive live UI

**Files:**
- Create: `ChessCamera/Features/Live/LiveRecordingView.swift`
- Create: `ChessCamera/UI/DigitalBoardView.swift`
- Create: `ChessCamera/UI/MoveListView.swift`
- Create: `ChessCamera/UI/FenBar.swift`
- Create: `ChessCamera/UI/StatusBanner.swift`

**Interfaces:**
- Consumes: ViewModel
- Produces: portrait stack + landscape split (UI_UX §4)

- [ ] **Step 1: `DigitalBoardView` from FEN / engine position, last-move highlight, 2 pt square grid, `Theme.boardLight/Dark`**

- [ ] **Step 2: HUD copy exactly as UI_UX §6.6** (Waiting for the board…, last SAN, Couldn’t read that move)

- [ ] **Step 3: `ViewThatFits` / `verticalSizeClass == .compact` for landscape split**

- [ ] **Step 4: Accessibility labels, announcement on commit, Reduce Motion snaps pieces**

- [ ] **Step 5: Previews for recording / disturbed / awaitingEdit**

- [ ] **Step 6: Device both orientations** — controls 44 pt, FEN copyable

- [ ] **Step 7: Commit** `feat: adaptive live recording HUD with digital twin`

---

### Task 14: Undo, edit last move, game over

**Files:**
- Create: `ChessCamera/Features/Replay/EditMoveSheet.swift`
- Create: `ChessCamera/Features/Replay/GameOverView.swift`
- Modify: ViewModel + `GameEngine`

**Interfaces:**
- Consumes: legal moves from ChessKit at previous position
- Produces: undo last; apply SAN from tap-from-to or ambiguous list; End game confirm; mate/stalemate → game over

- [ ] **Step 1: Undo calls `engine.undo()` and sets `lastCommitted = engine.occupancy()`**

- [ ] **Step 2: Edit sheet — from/to + promotion picker; Apply uses `apply(san:)`**

- [ ] **Step 3: `board.state` checkmate/stalemate presents Game Over (Undo still available)**

- [ ] **Step 4: Tests for undo + replace last ply PGN**

- [ ] **Step 5: Commit** `feat: undo and edit the last recorded move`

---

### Task 15: SwiftData history, replay, share PGN

**Files:**
- Create: `ChessCamera/Persistence/GameRecord.swift`
- Create: `ChessCamera/Features/Replay/ReplayView.swift`
- Create: `ChessCamera/App/AppContainer.swift`
- Modify: History, Game Over, app entry (`modelContainer`)

**Interfaces:**
- Consumes: `game.pgn`, `fen`
- Produces: persisted games; replay scrub; share `.pgn`

- [ ] **Step 1: `@Model GameRecord` as TRD §4**

- [ ] **Step 2: Save on End / mate; skip save if 0 moves**

- [ ] **Step 3: Replay via `Game(pgn:)` + step buttons + move list jump**

- [ ] **Step 4: Share sheet + copy PGN/FEN**

- [ ] **Step 5: History swipe delete with confirm**

- [ ] **Step 6: Commit** `feat: save games locally and replay or share PGN`

---

### Task 16: Video import + setup primer

**Files:**
- Create: `ChessCamera/Capture/AssetVideoSource.swift`
- Create: `ChessCamera/Features/Setup/SetupPrimerView.swift`
- Modify: History overflow

**Interfaces:**
- Consumes: `AVAssetReader`
- Produces: same pipeline; settle uses **video time**, not wall clock

- [ ] **Step 1: `AssetVideoSource` yielding frames with `CMTime` mapped to `ContinuousClock` duration** (pass timestamps into `SettleDetector.ingest`)

- [ ] **Step 2: PhotosPicker movies → detectingBoard**

- [ ] **Step 3: First-launch primer (APP_FLOW §4), UserDefaults flag**

- [ ] **Step 4: Run a known recording of `1. e4 e5 2. Nf3` end-to-end**

- [ ] **Step 5: Commit** `feat: import video through the same recording pipeline`

---

### Task 17: Hardening, demo script, polish

**Files:**
- Modify: copy, settle debug slider (optional Settings), tracking-lost banner
- Create: `docs/training-notes.md` if not already
- Modify: `README.md`

**Interfaces:** none new

- [ ] **Step 1: Play a complete casual game on the demo set (or the backup line from APP_FLOW §7)**

Log misses. Tune settle 300–1500 ms. Fix inferrer bugs with new fixture tests, not one-off UI hacks.

- [ ] **Step 2: Castling, capture, promotion on the physical board** — each must have a passing `MoveInferrer` test if it failed live

- [ ] **Step 3: Tracking lost → Adjust corners; backgrounding stops camera; no session leak on History**

- [ ] **Step 4: VoiceOver pass on History, Live HUD, Replay**

- [ ] **Step 5: Rehearse APP_FLOW demo script once with backup video**

- [ ] **Step 6: Commit** `fix: harden live recording for demo lighting and special moves`

---

## Day mapping

| Days | Tasks |
|---|---|
| 1–2 | 1–3, start 7 (camera) |
| 3–4 | 7–9 (detect, warp, corners) |
| 5–6 | 5 if not done, 10–11 (classifier, confirm start) |
| 7 | 4, 12 (settle + session loop) — Task 4 can be done on day 1 in parallel; keep it green before day 7 |
| 8 | 6 (if not already), 14 |
| 9 | 13, 15 |
| 10 | 16, 17 |

Do **Tasks 2–6 before relying on the camera.** MoveInferrer fixtures are the gate for “we can record a game.”

---

## Spec coverage

| Spec | Tasks |
|---|---|
| Live camera + video import | 7, 16 |
| Auto detect + 4-corner | 8, 9 |
| Classifier on own set + confirm start + orientation | 10, 11 |
| Occupancy + settle | 2, 4, 12 |
| Full-game inference + edit/undo | 6, 14 |
| Live board, FEN, PGN, replay, SwiftData | 13, 15 |
| Adaptive UI, a11y, demo | 13, 17 |
| No OpenCV / Stockfish / iCloud | Global constraints |
