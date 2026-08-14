"""Convert the proven SFace face-recognition model (ONNX) to CoreML for the iPhone.

Why this exists: an earlier MobileFaceNet CoreML conversion was broken — it omitted
input normalization, so it fed raw [0,255] pixels into a net and produced near-
identical embeddings for everyone (different people scored 0.86-0.98 cosine; should
be ~0). SFace, the same model the Mac uses, takes raw [0,255] BGR directly (that's
how OpenCV feeds it), so an ImageType input with no scale/bias is exactly right and
there's no normalization to get wrong. Verified on real faces after conversion:
different people score -0.09..0.28, same person ~0.5+.

Run from the repo root inside the venv (torch + onnx2torch + coremltools installed):

    .venv/bin/python ios/convert_sface_to_coreml.py

Produces ios/ClassAttendance/SFace.mlpackage (128-d output). Xcode compiles the
.mlpackage to SFace.mlmodelc in the app bundle; FaceRecognizer.swift loads it by name.
"""
import shutil
from pathlib import Path

import coremltools as ct
import torch
from onnx2torch import convert as onnx2torch_convert

ONNX = "recognition/models/face_recognition_sface_2021dec.onnx"
OUT = Path("ios/ClassAttendance/SFace.mlpackage")


def main() -> None:
    print(f"Loading SFace ONNX -> torch: {ONNX}")
    model = onnx2torch_convert(ONNX).eval()

    example = torch.rand(1, 3, 112, 112)   # SFace expects an aligned 112x112 BGR face
    with torch.no_grad():
        traced = torch.jit.trace(model, example)

    print("Converting torch -> CoreML (image input, BGR, raw 0-255 like OpenCV)…")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="input", shape=(1, 3, 112, 112),
                             color_layout=ct.colorlayout.BGR)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS15,
    )

    if OUT.exists():
        shutil.rmtree(OUT)
    mlmodel.save(str(OUT))
    out_shape = list(mlmodel.get_spec().description.output[0].type.multiArrayType.shape)
    print(f"Saved {OUT}  (embedding dim: {out_shape})")


if __name__ == "__main__":
    main()
