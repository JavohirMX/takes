#!/usr/bin/env bash
# Download Stockfish 17 NNUE nets into ChessCamera/Resources/NNUE/.
# ChessKitEngine looks for these filenames in Bundle.main.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/ChessCamera/Resources/NNUE"
mkdir -p "$DEST"

SMALL_NAME="nn-37f18f62d772.nnue"
BIG_NAME="nn-1111cefa1111.nnue"
BASE_URL="https://tests.stockfishchess.org/api/nn"

download() {
  local filename="$1"
  local out="$DEST/$filename"
  if [[ -f "$out" && -s "$out" ]]; then
    echo "Already present: $out ($(du -h "$out" | awk '{print $1}'))"
    return 0
  fi
  echo "Downloading $filename..."
  curl -fL --progress-bar -o "$out" "$BASE_URL/$filename"
  echo "Saved $out ($(du -h "$out" | awk '{print $1}'))"
}

download "$SMALL_NAME"

if [[ "${FETCH_BIG_NNUE:-0}" == "1" ]]; then
  download "$BIG_NAME"
else
  if [[ ! -f "$DEST/$BIG_NAME" ]]; then
    cp "$DEST/$SMALL_NAME" "$DEST/$BIG_NAME"
    echo "Mirrored small net as $BIG_NAME (set FETCH_BIG_NNUE=1 for the full net)."
  fi
fi

echo "Done. Regenerate the Xcode project if needed: xcodegen generate"
