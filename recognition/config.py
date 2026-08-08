"""Central configuration for the recognition prototype.

Everything tunable lives here so thresholds can be adjusted per room/camera
without touching pipeline code (see docs/02_ALGORITHM.md).
"""
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
DATA_DIR = BASE_DIR / "data"
TEMPLATES_DIR = DATA_DIR / "templates"   # enrolled face templates (per student)

for _d in (MODELS_DIR, DATA_DIR, TEMPLATES_DIR):
    _d.mkdir(parents=True, exist_ok=True)

# ── Model files (OpenCV Zoo ONNX) ────────────────────────────────────────────
# YuNet  = face DETECTION  (maps to YOLOv8/SCRFD role in the production design)
# SFace  = face RECOGNITION embedding (maps to ArcFace in the production design)
FACE_DETECT_MODEL = MODELS_DIR / "face_detection_yunet_2023mar.onnx"
FACE_RECOG_MODEL = MODELS_DIR / "face_recognition_sface_2021dec.onnx"

# ── Detection thresholds ─────────────────────────────────────────────────────
DETECT_SCORE_THRESHOLD = 0.7    # min confidence for a face detection
DETECT_NMS_THRESHOLD = 0.3
DETECT_TOP_K = 5000

# ── Recognition thresholds (see docs/02_ALGORITHM.md §4) ─────────────────────
# SFace uses cosine similarity; OpenCV's reference match threshold is 0.363.
# We keep it configurable and favour precision on "present".
COSINE_MATCH_THRESHOLD = 0.363

# Minimum inter-eye distance (pixels) to TRUST a frame for identity binding.
# Below this we keep tracking but don't (re)bind identity. This is the pixel
# budget from docs/01_FEASIBILITY.md made concrete.
MIN_INTEREYE_PX = 32            # hard floor; 64 is "reliable"
RELIABLE_INTEREYE_PX = 64

# ── Tracking / aggregation ───────────────────────────────────────────────────
IOU_MATCH_THRESHOLD = 0.3       # associate a detection to an existing track
MAX_TRACK_AGE = 15              # frames a track survives without a detection
MIN_FRAMES_PRESENT = 5          # a bound identity must persist >= this many
                                # sampled frames to count as PRESENT

# ── Capture ──────────────────────────────────────────────────────────────────
SAMPLE_FPS = 6                  # frames/sec we actually process (no need for all)
ATTENDANCE_SECONDS = 5          # length of the capture window per the concept
