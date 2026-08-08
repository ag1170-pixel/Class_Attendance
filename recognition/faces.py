"""Face detection + embedding, wrapping OpenCV's YuNet and SFace models.

- YuNet returns, per face: bbox + 5 landmarks (right eye, left eye, nose,
  right mouth, left mouth) + score.
- SFace turns an aligned face crop into a 128-D embedding; identities are
  compared by cosine similarity.

This is the prototype stand-in for the production YOLOv8+ArcFace stack; the
interface (detect -> embed -> match) is identical, so the pipeline is unchanged
when we upgrade the models.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List

import numpy as np

import cv2

from . import config


@dataclass
class Face:
    bbox: np.ndarray          # [x, y, w, h]
    landmarks: np.ndarray     # shape (5, 2): reye, leye, nose, rmouth, lmouth
    score: float
    raw: np.ndarray           # the raw 15-value YuNet row (needed by SFace align)

    @property
    def inter_eye_px(self) -> float:
        """Distance in pixels between the two eyes — our recognition quality gate."""
        reye, leye = self.landmarks[0], self.landmarks[1]
        return float(np.linalg.norm(reye - leye))

    @property
    def center(self) -> np.ndarray:
        x, y, w, h = self.bbox
        return np.array([x + w / 2.0, y + h / 2.0])


class FaceEngine:
    def __init__(self):
        if not config.FACE_DETECT_MODEL.exists():
            raise FileNotFoundError(
                f"Missing detector model: {config.FACE_DETECT_MODEL}\n"
                "Run: python -m recognition.download_models"
            )
        if not config.FACE_RECOG_MODEL.exists():
            raise FileNotFoundError(
                f"Missing recognizer model: {config.FACE_RECOG_MODEL}\n"
                "Run: python -m recognition.download_models"
            )
        self._detector = cv2.FaceDetectorYN.create(
            str(config.FACE_DETECT_MODEL),
            "",
            (320, 320),
            config.DETECT_SCORE_THRESHOLD,
            config.DETECT_NMS_THRESHOLD,
            config.DETECT_TOP_K,
        )
        self._recognizer = cv2.FaceRecognizerSF.create(
            str(config.FACE_RECOG_MODEL), ""
        )

    def detect(self, frame: np.ndarray) -> List[Face]:
        h, w = frame.shape[:2]
        self._detector.setInputSize((w, h))
        _, faces = self._detector.detect(frame)
        out: List[Face] = []
        if faces is None:
            return out
        for row in faces:
            bbox = row[0:4]
            lm = row[4:14].reshape(5, 2)
            score = float(row[14])
            out.append(Face(bbox=bbox, landmarks=lm, score=score, raw=row))
        return out

    def embed(self, frame: np.ndarray, face: Face) -> np.ndarray:
        """Aligned-crop -> L2-normalized embedding."""
        aligned = self._recognizer.alignCrop(frame, face.raw)
        feat = self._recognizer.feature(aligned)
        return feat.flatten().astype(np.float32)

    @staticmethod
    def cosine(a: np.ndarray, b: np.ndarray) -> float:
        denom = (np.linalg.norm(a) * np.linalg.norm(b)) + 1e-8
        return float(np.dot(a, b) / denom)
