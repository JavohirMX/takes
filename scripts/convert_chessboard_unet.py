#!/usr/bin/env python3
"""Convert ChessCamera/Resources TF.js U-Net++ → ChessboardUNet.mlpackage."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TFJS = REPO_ROOT / "ChessCamera" / "Resources" / "model.json"
DEFAULT_OUT = REPO_ROOT / "ChessCamera" / "ML" / "ChessboardUNet.mlpackage"
CACHE = Path(__file__).resolve().parent / ".cache"


def center_crop_square_resize(image, size: int = 128):
    """Match chessdetect-tfjs preprocessSource center-crop → 128."""
    import numpy as np
    from PIL import Image

    if not isinstance(image, Image.Image):
        image = Image.open(image).convert("RGB")
    else:
        image = image.convert("RGB")
    w, h = image.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    cropped = image.crop((left, top, left + side, top + side))
    resized = cropped.resize((size, size), Image.BILINEAR)
    arr = np.asarray(resized, dtype=np.float32) / 255.0
    return arr[None, ...]  # NHWC


def argmax_peaks(corners):
    """corners: (H, W, 4) → list of (x, y, score) for TL,TR,BR,BL."""
    import numpy as np

    h, w, c = corners.shape
    peaks = []
    for i in range(c):
        flat = corners[:, :, i].reshape(-1)
        idx = int(np.argmax(flat))
        y, x = divmod(idx, w)
        peaks.append((x, y, float(flat[idx])))
    return peaks


def _stub_missing_tf_deps() -> None:
    """tensorflowjs imports tensorflow_decision_forests, which has no macOS arm64 wheel."""
    import types

    if "tensorflow_decision_forests" not in sys.modules:
        stub = types.ModuleType("tensorflow_decision_forests")
        sys.modules["tensorflow_decision_forests"] = stub


def tfjs_to_saved_model(tfjs_json: Path, saved_dir: Path) -> None:
    if saved_dir.exists():
        shutil.rmtree(saved_dir)
    saved_dir.parent.mkdir(parents=True, exist_ok=True)
    _stub_missing_tf_deps()
    from tfjs_graph_converter.api import graph_model_to_saved_model

    graph_model_to_saved_model(str(tfjs_json), str(saved_dir))


def convert_coreml(saved_dir: Path, out_path: Path):
    import coremltools as ct

    mlmodel = ct.convert(
        str(saved_dir),
        source="tensorflow",
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        inputs=[ct.TensorType(name="input_image", shape=(1, 128, 128, 3))],
    )
    mlmodel.author = "Elucidation (converted for Chess Camera)"
    mlmodel.short_description = (
        "U-Net++ chessboard segmentation + 4 corner heatmaps "
        "(https://github.com/Elucidation/chessdetect-tfjs)"
    )
    mlmodel.license = "MIT"
    if out_path.exists():
        shutil.rmtree(out_path) if out_path.is_dir() else out_path.unlink()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out_path))
    return mlmodel


def expand_fused_conv2d_graph(graph_def):
    """Replace TF.js _FusedConv2D nodes with Conv2D (+ BiasAdd) (+ Relu) for coremltools."""
    from tensorflow.core.framework import graph_pb2, node_def_pb2

    new_graph = graph_pb2.GraphDef()
    new_graph.versions.CopyFrom(graph_def.versions)
    if graph_def.library.ByteSize():
        new_graph.library.CopyFrom(graph_def.library)

    for node in graph_def.node:
        if node.op != "_FusedConv2D":
            new_graph.node.append(node)
            continue

        fused = [x.decode("utf-8") if isinstance(x, bytes) else str(x) for x in node.attr["fused_ops"].list.s]
        # Conv2D
        conv = new_graph.node.add()
        conv.name = f"{node.name}/Conv2D"
        conv.op = "Conv2D"
        conv.input.extend([node.input[0], node.input[1]])
        for key in ("T", "strides", "padding", "data_format", "dilations", "use_cudnn_on_gpu", "explicit_paddings"):
            if key in node.attr:
                conv.attr[key].CopyFrom(node.attr[key])

        current = conv.name
        next_input_idx = 2
        for op_name in fused:
            if op_name == "BiasAdd":
                bias = new_graph.node.add()
                bias.name = f"{node.name}/BiasAdd"
                bias.op = "BiasAdd"
                bias.input.extend([current, node.input[next_input_idx]])
                next_input_idx += 1
                if "T" in node.attr:
                    bias.attr["T"].CopyFrom(node.attr["T"])
                if "data_format" in node.attr:
                    bias.attr["data_format"].CopyFrom(node.attr["data_format"])
                current = bias.name
            elif op_name == "Relu":
                act = new_graph.node.add()
                act.name = f"{node.name}/Relu"
                act.op = "Relu"
                act.input.append(current)
                if "T" in node.attr:
                    act.attr["T"].CopyFrom(node.attr["T"])
                current = act.name
            elif op_name == "Relu6":
                act = new_graph.node.add()
                act.name = f"{node.name}/Relu6"
                act.op = "Relu6"
                act.input.append(current)
                if "T" in node.attr:
                    act.attr["T"].CopyFrom(node.attr["T"])
                current = act.name
            else:
                raise NotImplementedError(f"Unsupported fused op in _FusedConv2D: {op_name}")

        # Identity with original name so consumers keep working.
        ident = new_graph.node.add()
        ident.name = node.name
        ident.op = "Identity"
        ident.input.append(current)
        if "T" in node.attr:
            ident.attr["T"].CopyFrom(node.attr["T"])

    return new_graph


def saved_model_to_defused_saved_model(saved_dir: Path, defused_dir: Path) -> Path:
    """Freeze + expand _FusedConv2D, then re-export as a TF1 SavedModel directory."""
    import tensorflow as tf
    from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2

    model = tf.saved_model.load(str(saved_dir))
    concrete = model.signatures.get("serving_default") or list(model.signatures.values())[0]
    frozen_func = convert_variables_to_constants_v2(concrete, lower_control_flow=False)
    graph_def = expand_fused_conv2d_graph(frozen_func.graph.as_graph_def(add_shapes=True))

    if defused_dir.exists():
        shutil.rmtree(defused_dir)
    defused_dir.parent.mkdir(parents=True, exist_ok=True)

    # Also keep a .pb for debugging / reconvert.
    pb_path = CACHE / "chessboard_unet_defused.pb"
    pb_path.write_bytes(graph_def.SerializeToString())

    g = tf.Graph()
    with g.as_default():
        tf.import_graph_def(graph_def, name="")
        with tf.compat.v1.Session(graph=g) as sess:
            in_t = sess.graph.get_tensor_by_name("input_image:0")
            corners_t = sess.graph.get_tensor_by_name("Identity:0")
            seg_t = sess.graph.get_tensor_by_name("Identity_1:0")
            tf.compat.v1.saved_model.simple_save(
                sess,
                str(defused_dir),
                inputs={"input_image": in_t},
                outputs={"corners": corners_t, "segmentation": seg_t},
            )
    print(f"Wrote defused SavedModel → {defused_dir}")
    return defused_dir


def convert_via_defused_frozen(saved_dir: Path, out_path: Path):
    defused_dir = CACHE / "chessboard_unet_defused_savedmodel"
    saved_model_to_defused_saved_model(saved_dir, defused_dir)
    return convert_coreml(defused_dir, out_path)


def smoke_tf(saved_dir: Path, image_path: Path) -> None:
    import tensorflow as tf

    batch = center_crop_square_resize(image_path)
    model = tf.saved_model.load(str(saved_dir))
    concrete = model.signatures.get("serving_default") or list(model.signatures.values())[0]
    out = concrete(tf.constant(batch))
    # Find corners tensor by shape
    corners = None
    for v in out.values():
        shape = tuple(v.shape)
        if len(shape) == 4 and shape[-1] == 4:
            corners = v.numpy()[0]
            break
    if corners is None:
        raise RuntimeError(f"Could not find corners output in {list(out.keys())}")
    peaks = argmax_peaks(corners)
    labels = ["TL", "TR", "BR", "BL"]
    print("Smoke peaks (128-space):")
    for label, (x, y, score) in zip(labels, peaks):
        print(f"  {label}: ({x}, {y}) score={score:.4f}")
        if not (score == score):  # NaN
            raise SystemExit("Non-finite peak score")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tfjs", type=Path, default=DEFAULT_TFJS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--smoke", type=Path, default=None, help="Optional image for peak smoke test")
    parser.add_argument("--skip-coreml", action="store_true", help="Only build SavedModel")
    args = parser.parse_args()

    tfjs = args.tfjs.resolve()
    if not tfjs.is_file():
        raise SystemExit(f"Missing TF.js model.json: {tfjs}")
    bin_path = tfjs.parent / "group1-shard1of1.bin"
    if not bin_path.is_file():
        raise SystemExit(f"Missing weights beside model.json: {bin_path}")

    saved_dir = CACHE / "chessboard_unet_savedmodel"
    print(f"Converting TF.js → SavedModel\n  {tfjs}\n  → {saved_dir}")
    tfjs_to_saved_model(tfjs, saved_dir)
    print("SavedModel OK")

    if args.smoke:
        smoke_tf(saved_dir, args.smoke.resolve())

    if args.skip_coreml:
        return

    out = args.out.resolve()
    print(f"Converting SavedModel → Core ML\n  → {out}")
    try:
        convert_coreml(saved_dir, out)
        print("Core ML conversion OK")
    except Exception as exc:
        print(f"Direct Core ML convert failed ({type(exc).__name__})")
        print("Trying defused frozen graph path…")
        convert_via_defused_frozen(saved_dir, out)
        print("Core ML conversion via defused frozen graph OK")

    if args.smoke:
        smoke_tf(saved_dir, args.smoke.resolve())
        smoke_coreml(out, args.smoke.resolve())


def smoke_coreml(mlpackage: Path, image_path: Path) -> None:
    import coremltools as ct
    import numpy as np

    batch = center_crop_square_resize(image_path).astype(np.float32)
    ml = ct.models.MLModel(str(mlpackage))
    in_name = ml.get_spec().description.input[0].name
    out = ml.predict({in_name: batch})
    corners = None
    for value in out.values():
        arr = np.asarray(value)
        if arr.ndim == 4 and arr.shape[-1] == 4:
            corners = arr[0]
            break
        if arr.ndim == 3 and arr.shape[-1] == 4:
            corners = arr
            break
    if corners is None:
        raise RuntimeError(f"Could not find corners in Core ML outputs {list(out.keys())}")
    peaks = argmax_peaks(corners)
    print("Core ML smoke peaks (128-space):")
    for label, (x, y, score) in zip(["TL", "TR", "BR", "BL"], peaks):
        print(f"  {label}: ({x}, {y}) score={score:.4f}")
        if score != score:
            raise SystemExit("Non-finite Core ML peak score")


if __name__ == "__main__":
    main()
