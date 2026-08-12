"""Convert the proven SFace ONNX face model to CoreML for the iPhone.

Why: the previously-bundled MobileFaceNet CoreML was broken — its conversion
omitted input normalization, so it output near-identical embeddings for everyone
(different people scored 0.86–0.98 cosine; verified). SFace takes raw [0,255] BGR
(exactly what a CoreML image input provides) and, once converted, discriminates
cleanly on-device: different people score ~0.0–0.28, the same person ~0.5+.

Run (needs: torch, onnx2torch, onnx, coremltools):
    python ios/convert_sface_to_coreml.py
Produces ios/ClassAttendance/SFace.mlpackage.
"""
import shutil
from pathlib import Path

import coremltools as ct
import torch
from onnx2torch import convert as onnx2torch_convert

ROOT = Path(__file__).resolve().parent.parent
ONNX = ROOT / "recognition/models/face_recognition_sface_2021dec.onnx"
OUT = ROOT / "ios/ClassAttendance/SFace.mlpackage"


def main() -> None:
    model = onnx2torch_convert(str(ONNX)).eval()
    with torch.no_grad():
        traced = torch.jit.trace(model, torch.rand(1, 3, 112, 112))

    mlmodel = ct.convert(
        traced,
        # SFace expects a 112x112 BGR face, raw pixel values (no scale/bias) —
        # matching how OpenCV feeds it on the Mac.
        inputs=[ct.ImageType(name="input", shape=(1, 3, 112, 112),
                             color_layout=ct.colorlayout.BGR)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS15,
    )
    if OUT.exists():
        shutil.rmtree(OUT)
    mlmodel.save(str(OUT))
    print("Saved", OUT)


if __name__ == "__main__":
    main()
