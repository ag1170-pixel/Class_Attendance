# Recognition Accuracy — the formula, and why no one's attendance is lost

Goal: **a present student must never be silently marked absent.** Accuracy here
is not one number — it's a decision rule that (a) recognises confidently when it
can, and (b) when unsure, **surfaces the student for a one-tap teacher check**
instead of dropping them. The teacher review is the safety net; the algorithm's
job is to make sure nobody falls through it.

Same formula on the Mac (server) and on the iPhone (Core ML) — only the model
that produces the embedding differs.

---

## 1. The pipeline (recall-first, review-backed)

```
clip → sample frames → detect faces (YOLOv8 / Vision)
     → TRACK each face across frames (recognise-once-then-track: a mask or a
       turned head never drops a person)
     → on the best frame per track, embed the face (ArcFace / SFace / Core ML)
     → match against THIS class roster → classify (below) → aggregate over the clip
     → present / needs-review / absent  +  any unknown (not-enrolled) faces
```

Two design choices do most of the "don't lose anyone" work:

- **Track, don't re-detect.** Once a face is picked up, an object tracker follows
  that person every frame. Identity only needs **one** good frame; tracking
  carries it through the bad ones. This kills the biggest cause of lost
  attendance: momentarily losing a face.
- **Match only against the class roster** (30–60 enrolled faces), not the whole
  institution — fewer look-alikes, higher precision *and* recall.

---

## 2. The matching formula

Embeddings are **L2-normalized**, so similarity is cosine (dot product), in
[-1, 1]. A student may have **several enrolled templates** (front, slight angles)
— more templates = higher recall.

For a detected face embedding **e** and each enrolled student *k* with templates
`T_k`:

```
score(k)   = max_{t in T_k}  cosine(e, t)      # best-matching template for k
s1, k1     = the highest score and the student who owns it   (best match)
s2         = the second-highest score across OTHER students  (runner-up)
margin     = s1 − s2                                          (how clear the win is)
```

**Per-frame decision for the best match k1:**

| Condition | Result |
|---|---|
| `s1 ≥ τ_high` **and** `margin ≥ m` | **confident** match to k1 |
| `τ_low ≤ s1 < τ_high` **or** `margin < m` | **uncertain** → mark k1 as *needs-review* |
| `s1 < τ_low` | not this student (leave the face **unknown**) |

- **τ_high** — auto-present cutoff (favour precision here; a false auto-present is
  a silent proxy).
- **τ_low** — the "don't drop them" floor. Between the two thresholds we do **not**
  decide absent — we flag for the teacher.
- **margin m** — guards against look-alikes / identical-twin confusion: even a
  high `s1` is only trusted if it clearly beats the runner-up.

---

## 3. Aggregating over the clip (temporal voting)

A student isn't judged on one frame. Over the ~5-second clip we keep, per student:

```
best_s1     = max s1 seen for them
frames_seen = number of sampled frames their track was matched
```

Final status:

| | Rule |
|---|---|
| **Present (auto)** | `best_s1 ≥ τ_high`, `margin ≥ m`, and `frames_seen ≥ K` |
| **Needs review** | matched at least once with `best_s1 ≥ τ_low` but not confident |
| **Absent** | never matched above `τ_low` in the whole clip |
| **Unknown face** | a tracked face that matched **no** enrolled student → "not enrolled", shown to the teacher to locate + invite |

`K` (minimum frames) removes one-frame flukes without hurting recall, because
tracking gives many frames per person.

**This is the guarantee:** a student who appears is either auto-present or
**needs-review** — the only way to be marked absent is to never clear `τ_low` in
*any* frame of the clip, and even then, unknown-face surfacing + manual add catch
capture failures. Nobody is silently dropped.

---

## 4. Default thresholds (tune on real room footage)

| Symbol | Meaning | Start value |
|---|---|---|
| `τ_high` | auto-present | **0.45** cosine (SFace ref ≈ 0.363; we sit above it) |
| `τ_low` | review floor | **0.30** |
| `m` | winner margin | **0.06** |
| `K` | min frames present | **3** |
| IED gate | min inter-eye px to trust a frame for identity | **32** (64 preferred) |

These are **configuration**, tuned per institution/room from a labelled clip:
raise `τ_high` if you see any false auto-present; lower `τ_low` / raise template
count if any real student lands in review too often.

---

## 5. What each side runs

- **Mac / server:** YOLOv8 (detect) + BoT-SORT (track) + ArcFace (embed), or the
  current OpenCV YuNet+SFace prototype. Full formula in `recognition/`.
- **iPhone (Core ML):** Vision detects + tracks faces on-device; a converted
  **ArcFace/FaceNet Core ML** model produces the 512-d embedding; the **same**
  τ_high / τ_low / margin / K rule runs locally. No face image leaves the phone —
  only the present/absent result.

---

## 6. Practical accuracy levers (in priority order)

1. **Enroll 3–5 templates per student** from slightly different angles — the
   single biggest recall win.
2. **Good capture geometry** — camera sees faces, adequate resolution (≥64px
   inter-eye). See `01_FEASIBILITY.md`.
3. **Track-through-occlusion** (already implemented) — don't lose masked/turned faces.
4. **Second recognition pass** at a random moment in the class — catches anyone
   missed in the first clip.
5. **Human-in-the-loop review** — the final, absolute guarantee against a lost mark.
