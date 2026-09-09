# Chess Camera

iPhone prototype for a 10-day Apple Developer Academy challenge: point a camera at a physical chessboard, reconstruct the game, and leave with PGN you can replay or paste into another tool.

This repo currently holds the planning set only. Implementation follows [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md).

## Docs

| Doc | What it is |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Product: problem, users, 10-day success bar, stories, non-goals |
| [docs/TRD.md](docs/TRD.md) | Technical: pipeline, ChessKit, Core ML, settle + move inference |
| [docs/UI_UX.md](docs/UI_UX.md) | Interface: dark camera-tool UI, adaptive live layout, states |
| [docs/APP_FLOW.md](docs/APP_FLOW.md) | Flow: phase machine, setup ritual, demo script |
| [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | 10-day build tasks |

## Locked scope (short)

- **Platform:** iPhone, iOS 18+, SwiftUI, AVFoundation
- **Vision:** Vision + Core ML on *your* chess set. No OpenCV, no paid AI APIs, no Stockfish
- **Game:** standard start → occupancy changes + chess rules → full-game PGN (including special moves)
- **Calibration:** auto board detect, 4-corner fallback
- **UX:** auto-accept moves; edit/undo last ply; wait until the board is still
- **Output:** live digital board, FEN, replay, SwiftData history, share PGN

## Requirements (when code exists)

- Xcode 16+
- iOS 18+
- Physical iPhone for camera (simulator is fine for chess-logic tests)

## Research question

Can a normal iPhone camera turn a physical game into a digitally reviewable game under controlled conditions — and can chess rules fix what vision gets wrong?
