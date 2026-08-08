"""Recognition prototype for the camera-based class attendance system.

Modules:
  config          tunable thresholds (one place)
  capture         pluggable capture sources (webcam / file / RTSP)
  faces           YuNet detection + SFace embedding (prototype for YOLOv8+ArcFace)
  tracker         IoU tracker (prototype for ByteTrack/BoT-SORT)
  roster          enrolled-student templates + roster-scoped matching
  pipeline        recognise-once-then-track -> present/absent
  enroll          CLI: enrol a student's face (one-time scan)
  take_attendance CLI: run an attendance session
"""
