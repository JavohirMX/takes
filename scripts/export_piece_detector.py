#!/usr/bin/env python3
"""Export YOLO piece-detector weights to Core ML for Chess Camera.

YOLO11's C2PSA block often fails torch→Core ML (NMS pipeline). Fall back to
ONNX → coremltools; the iOS runtime decodes the raw YOLO head.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WEIGHTS = Path.home() / "Downloads" / "best.pt"
DEFAULT_OUT = REPO_ROOT / "ChessCamera" / "ML" / "ChessPieceYOLO.mlpackage"
DEFAULT_NAMES = REPO_ROOT / "ChessCamera" / "ML" / "ChessPieceYOLO.classes.txt"


def class_names(model) -> list[str]:
    names = model.names
    if isinstance(names, dict):
        return [str(names[i]) for i in range(len(names))]
    return [str(n) for n in names]


def write_class_names(names: list[str], dest: Path) -> None:
    dest.write_text("\n".join(names) + "\n")
    print("classes:", names)
    print("wrote", dest)


def place(exported: Path, out: Path) -> None:
    exported = exported.resolve()
    out = out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    if exported != out:
        if out.exists():
            shutil.rmtree(out)
        shutil.move(str(exported), str(out))
    print("wrote", out)


def export_coreml_nms(model, imgsz: int) -> Path:
    return Path(str(model.export(format="coreml", nms=True, imgsz=imgsz)))


def export_via_onnx(model, imgsz: int, names: list[str]) -> Path:
    import coremltools as ct

    onnx_path = Path(str(model.export(format="onnx", imgsz=imgsz, simplify=True, nms=False)))
    try:
        mlmodel = ct.convert(
            str(onnx_path),
            convert_to="mlprogram",
            inputs=[
                ct.ImageType(
                    name="images",
                    shape=(1, 3, imgsz, imgsz),
                    scale=1 / 255.0,
                    color_layout=ct.colorlayout.RGB,
                )
            ],
            minimum_deployment_target=ct.target.iOS16,
        )
        mlmodel.user_defined_metadata["class_names"] = ",".join(names)
        mlmodel.user_defined_metadata["imgsz"] = str(imgsz)
        dest = onnx_path.with_name(onnx_path.stem + ".mlpackage")
        if dest.exists():
            shutil.rmtree(dest)
        mlmodel.save(str(dest))
        return dest
    finally:
        onnx_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--names-out", type=Path, default=DEFAULT_NAMES)
    parser.add_argument("--imgsz", type=int, default=640)
    args = parser.parse_args()

    if not args.weights.is_file():
        raise SystemExit(f"Missing weights: {args.weights}")

    from ultralytics import YOLO

    model = YOLO(str(args.weights))
    names = class_names(model)
    write_class_names(names, args.names_out)

    try:
        exported = export_coreml_nms(model, args.imgsz)
        print("Core ML NMS export succeeded")
    except Exception as exc:
        print(f"Core ML NMS export failed ({exc}); falling back to ONNX → Core ML")
        exported = export_via_onnx(model, args.imgsz, names)

    place(exported, args.out)


if __name__ == "__main__":
    main()
