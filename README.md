# Chess Camera

iPhone prototype: point a camera at a physical chessboard, reconstruct the game, and leave with PGN you can replay or paste into another tool.

## Status

SwiftUI app on iOS 18+ / Swift 6. Chess rules, FEN, and PGN come from [ChessKit](https://github.com/chesskit-app/chesskit-swift). Vision localizes the board; occupancy settle + legal-move inference record the game. **No Core ML model is bundled yet** — confirm-start uses the standard position, and occupancy uses a non-ML heuristic until you train `PieceClassifier.mlmodel` (see [docs/training-notes.md](docs/training-notes.md)).

## Docs

| Doc | What it is |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Product: problem, users, 10-day success bar, stories, non-goals |
| [docs/TRD.md](docs/TRD.md) | Technical: pipeline, ChessKit, Core ML, settle + move inference |
| [docs/UI_UX.md](docs/UI_UX.md) | Interface: dark camera-tool UI, adaptive live layout, states |
| [docs/APP_FLOW.md](docs/APP_FLOW.md) | Flow: phase machine, setup ritual, demo script |
| [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | 10-day build tasks |
| [docs/training-notes.md](docs/training-notes.md) | How to export 64 crops and train a classifier later |

## Requirements

- Xcode 16+
- iOS 18+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate `ChessCamera.xcodeproj` from `project.yml`
- Physical iPhone for live camera, board detect, and a real game
- Simulator: chess-logic tests, History, primer, confirm-start (standard FEN), live HUD, replay, share/copy PGN

```bash
xcodegen generate
xcodebuild -scheme ChessCamera -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Locked scope

- **Platform:** iPhone, iOS 18+, SwiftUI, AVFoundation
- **Vision:** Vision + optional Core ML on *your* chess set. OpenCV imgproc only, for grid refine at confirm-start. No paid AI APIs, no Stockfish, no iCloud
- **Game:** standard start → occupancy changes + chess rules → full-game PGN
- **Calibration:** auto board detect, 4-corner fallback
- **UX:** auto-accept moves; edit/undo last ply; wait until the board is still
- **Output:** live digital board, FEN, replay, SwiftData history, share PGN
