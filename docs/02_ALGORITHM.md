# Recognition Algorithm — "Recognize Once, Then Track"

**Purpose:** Turn a short video clip (from the room CCTV, or a teacher's 5s iPhone video) into a reliable present/absent list bound to real enrolled students.

**Design origin:** Synthesized from three reference projects the café-style tracking uses, plus the identity layer they all lack.

---

## 1. What the reference repos taught us

| Repo | Stack | What we take | What we fix |
|---|---|---|---|
| saimj7/People-Counting-in-Real-Time | SSD-MobileNet + centroid tracker | The "detect once, follow after" concept | Centroid tracker loses IDs on occlusion; SSD is dated → use YOLOv8 + ByteTrack |
| Ultralytics discussion #2386 | YOLOv8 export → CoreML/ONNX; DeepSORT | YOLOv8 → **Core ML** for on-device iPhone path | DeepSORT is extra glue → YOLOv8 has trackers built in |
| topic: person-detection-and-tracking | YOLOv5/v8 + DeepSORT/ByteTrack + Re-ID | The modern standard stack | All are **anonymous**; we add face-identity binding |

**Core insight:** café systems answer *"how long was someone here?"* (anonymous). Attendance answers *"who was here?"* (identity). We keep their tracking and add a face-recognition identity layer on top.

---

## 2. The pipeline

```
video clip (N seconds)
      │
      ▼
[1] Frame sampling            ── sample ~5–10 fps (no need for every frame)
      │
      ▼
[2] Person detection          ── YOLOv8 (person class), per sampled frame
      │
      ▼
[3] Multi-object tracking     ── ByteTrack / BoT-SORT (built into YOLOv8)
      │                           → each person gets a stable track_id across frames
      ▼
[4] Face detect + quality gate── on each tracked person's crop, find a face
      │                           accept only if: IED ≥ 64px, frontal, in focus
      ▼
[5] Face embedding + match     ── ArcFace/FaceNet embedding → cosine-match
      │                           against THIS CLASS ROSTER only
      │                           → bind track_id → student_id (once, then confirm)
      ▼
[6] Temporal aggregation       ── present if bound track seen ≥ K frames / ≥ T sec
      │                           above similarity threshold τ
      ▼
[7] Output                     ── present/absent + confidence per student
      │
      ▼
teacher tick/cross review → confirm → store
```

---

## 3. Why each choice

- **YOLOv8 for detection** — fast, accurate, exports to Core ML (iOS) and ONNX/TensorRT (server). Replaces the dated SSD-MobileNet.
- **ByteTrack/BoT-SORT for tracking** — Kalman motion model + IoU (+ appearance for BoT-SORT). Survives occlusion and path-crossing that the centroid tracker fails on. **Built into the YOLOv8 API** (`model.track(source, tracker="botsort.yaml")`) — minimal glue code.
- **Recognize once, then track** — the identity only needs to be established from **one good frame per person**. This is what defeats the pixel-density problem: a student's face must be ≥64px-between-eyes in *at least one* frame (e.g. when they glance toward the camera or walk in), not in every frame. Tracking carries the identity through all the small/turned/occluded frames.
- **Match against the class roster only** — comparing against ~30–60 enrolled faces (not the whole university) is faster and dramatically reduces false matches. Roster comes from the schedule.
- **Temporal aggregation** — one lucky false match won't mark someone present; the identity has to persist across multiple frames.
- **ArcFace/FaceNet embeddings** — state-of-the-art face embeddings; store the enrolled template as a vector, match by cosine similarity.

---

## 4. Thresholds & tuning (favor precision on "present")

- **τ (cosine similarity)** for a positive identity match: tuned high, because a **false "present" is worse than a false "absent"** — the teacher reviews absentees anyway, so misses get caught, but a false-present is a silent proxy.
- **IED gate ≥ 64px** for the recognition frame (32px hard floor). Below this, don't attempt identity — keep tracking anonymously until a better frame appears.
- **K frames / T seconds** minimum for "present" — start at ~1.5s of tracked presence.
- Every threshold is a config value, tuned on real footage from the target rooms.

---

## 5. Anti-proxy / liveness

- **Recognize-once-then-track** inherently blocks "stand at the door and leave" — the track must persist inside the room.
- **Liveness**: natural motion across the tracked frames (a printed photo doesn't walk, blink, or turn). Landmark movement (Vision on iOS; face-landmark model on server) confirms a live face.
- **One face per identity per session** — the same student can't be matched to two tracks; the same track can't hold two identities.
- **Trigger window**: attendance only accepted for the scheduled class time + room, and only after the teacher's authenticated in-room trigger.

---

## 6. Two capture paths, one pipeline

| Path | Where detection/tracking runs | When used |
|---|---|---|
| **A. Room CCTV (primary)** | Server (GPU) pulls 5s clip via ONVIF Profile G, runs full pipeline | Normal case; good campus cameras |
| **B. Teacher iPhone 5s video (fallback)** | Can run on-device (YOLOv8→Core ML + face embedding) or upload clip to server | Camera unavailable/poor, or small rooms |

Both feed the **same** recognition service and produce the same present/absent output → the teacher review screen is identical either way.

---

## 7. Accuracy expectations (be honest)

- In good conditions (adequate resolution, one good frontal frame per student), expect high accuracy — literature reports 90–96% in controlled conditions.
- Real-world dips come from: a student never showing a good frame, heavy occlusion, bad lighting, or a camera seeing backs of heads.
- **The teacher review step is the safety net** — the system pre-fills, the human confirms. We never auto-submit. This is also what makes it academically and legally defensible.

---

## 8. Build/eval plan for this module

1. Prototype on a sample classroom video (YOLOv8 + BoT-SORT + a face-recognition lib e.g. `insightface`/ArcFace).
2. Measure: per-student recognition rate, false-present rate, false-absent rate.
3. Tune τ, IED gate, K on that footage.
4. Export YOLOv8 → Core ML for the on-device iPhone path.
5. Wrap as a service with a clean API: `POST /recognize {clip, roster} → [{student_id, status, confidence}]`.
