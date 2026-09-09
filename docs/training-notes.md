# Training notes — Chess Camera piece classifier

The app does **not** ship a trained Core ML model in this repository. Recording, confirm-start, inference, replay, and PGN all work without one.

## What the app does today

- `CoreMLPieceClassifier.loadBundled()` looks for `PieceClassifier.mlmodelc` or `PieceClassifier.mlmodel` in the app bundle.
- If the file is missing, load returns `nil` and confirm-start uses **Use standard starting position**.
- Occupancy during a game uses a brightness/variance heuristic (`HeuristicOccupancyEstimator`), not Core ML.
- On the confirm-start screen, **Export 64 crops** writes 64 PNGs named `a1.png`…`h8.png` plus a README. Share that folder to a Mac for labeling.

## How to train later (physical set)

1. Mount the phone the way you will record. Standard starting position, demo lighting.
2. New Game → Looks good (or Adjust corners) → Confirm start → **Export 64 crops**.
3. Repeat for an empty board and for each piece type on light and dark squares.
4. Label 13 classes: `empty` plus the 12 piece types (`whitePawn` … `blackKing`).
5. Train an image classifier in Create ML (Xcode) targeting iOS. MobileNetV2 / Create ML default is fine.
6. Export `PieceClassifier.mlmodel` and add it to the `ChessCamera` target (same name).
7. Rebuild. Confirm start will classify 64 squares when the model is present.

Do not use a public chess-piece dataset as the primary model. Fine-tune on this set only if Create ML on your photos is not enough.

No photos from a physical board were taken for this slice. No `.mlmodel` was trained.
