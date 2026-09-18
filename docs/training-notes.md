# Training notes — Takes

## Piece classifier

The app does **not** require a trained piece Core ML model. Recording, confirm-start, inference, replay, and PGN all work without one.

### What the app does today

- `CoreMLPieceClassifier.loadBundled()` looks for `PieceClassifier.mlmodelc` or `PieceClassifier.mlmodel` in the app bundle.
- If the file is missing, load returns `nil` and confirm-start uses **Use standard starting position**.
- Occupancy during a game uses a brightness/variance heuristic (`HeuristicOccupancyEstimator`), not Core ML.
- On the confirm-start screen, **Export 64 crops** writes 64 PNGs named `a1.png`…`h8.png` plus a README. Share that folder to a Mac for labeling.

### How to train later (physical set)

1. Mount the phone the way you will record. Standard starting position, demo lighting.
2. New Game → Looks good (or Adjust corners) → Confirm start → **Export 64 crops**.
3. Repeat for an empty board and for each piece type on light and dark squares.
4. Label 13 classes: `empty` plus the 12 piece types (`whitePawn` … `blackKing`).
5. Train an image classifier in Create ML (Xcode) targeting iOS. MobileNetV2 / Create ML default is fine.
6. Export `PieceClassifier.mlmodel` and add it to the `ChessCamera` target (same name).
7. Rebuild. Confirm start will classify 64 squares when the model is present.

Do not use a public chess-piece dataset as the primary model. Fine-tune on this set only if Create ML on your photos is not enough.

No photos from a physical board were taken for this slice. No piece `.mlmodel` was trained.

---

## Board localizer (Vision + ML compare)

Board Studio runs **Vision** (`VNDetectRectangles` + grid score) and, when bundled, a **Core ML U-Net++** heatmap model side by side.

| Source | Overlay | Role |
|--------|---------|------|
| Vision | White | Default active path; temporal consensus + corner tracker |
| ML | Accent | Optional A/B proposal from `ChessboardUNet.mlpackage` |

- Segmented control **Vision | ML** picks which quad drives handles, warp thumbnail, and **Looks good**.
- Recording still hard-locks the confirmed quad; there is **no** ML tracking mid-game.
- If `ChessboardUNet` is missing, `HeatmapBoardLocalizer.loadBundled()` returns `nil` and the app stays Vision-only.

### Model provenance

Weights in `ChessCamera/Resources/` (`model.json`, `group1-shard1of1.bin`) are from [Elucidation/chessdetect-tfjs](https://github.com/Elucidation/chessdetect-tfjs) (MIT). See `ChessCamera/Resources/NOTICE`.

**Caveat:** pretrained on ~10k Blender synthetics. Expect domain shift on wood boards / your lighting — that is what the Board Studio compare is for (keep / fine-tune / drop).

### Convert TF.js → Core ML (`uv`)

From repo root:

```bash
cd scripts
uv sync --python 3.11
uv run python convert_chessboard_unet.py \
  --tfjs ../ChessCamera/Resources/model.json \
  --out ../ChessCamera/ML/ChessboardUNet.mlpackage
```

Optional smoke image:

```bash
uv run python convert_chessboard_unet.py \
  --tfjs ../ChessCamera/Resources/model.json \
  --out ../ChessCamera/ML/ChessboardUNet.mlpackage \
  --smoke /path/to/board.jpg
```

The script expands TF.js `_FusedConv2D` ops (coremltools cannot load them directly), then writes `ChessCamera/ML/ChessboardUNet.mlpackage`. Regenerate the Xcode project after adding/removing the package (`xcodegen generate`).

### Board Studio compare protocol

1. Mount the phone as for a real game.
2. New Game → Board Studio.
3. Wait until Vision and/or ML overlays appear.
4. Switch **Vision | ML**; check handles + warp for each.
5. Confirm the better source with **Looks good**, then play a few moves.
6. Decide: keep ML, fine-tune on your set, or drop and stay Vision-only.
