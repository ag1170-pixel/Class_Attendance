import AVFoundation
import SwiftUI
import Vision

/// One tracked person on screen: a Vision object tracker + the identity bound to
/// them (recognise once, then the tracker carries it through masks/turns).
final class TrackedFace {
  var request: VNTrackObjectRequest
  var box: CGRect
  var register: String?
  var name: String?
  var present = false  // matched at the "present" threshold
  var score: Float = 0 // match confidence
  init(box: CGRect) {
    self.box = box
    request = VNTrackObjectRequest(
      detectedObjectObservation:
        VNDetectedObjectObservation(boundingBox: box))
  }
}

struct LiveBox {
  let rect: CGRect
  let name: String?
  let present: Bool
}

/// On-device live capture: detect + track faces, recognise each ONCE (Vision
/// feature print → FaceRecognizer), then the tracker follows them. Publishes the
/// boxes and the set of register numbers seen present. Fully on-device.
@MainActor
final class FaceTracker: NSObject, ObservableObject,
  AVCaptureVideoDataOutputSampleBufferDelegate
{
  let session = AVCaptureSession()
  @Published var boxes: [LiveBox] = []
  @Published var presentRegisters: Set<String> = []
  @Published var unavailable: String?

  private let queue = DispatchQueue(label: "face.tracker")
  private let sequence = VNSequenceRequestHandler()
  private nonisolated(unsafe) var tracks: [TrackedFace] = []  // capture-queue only
  private nonisolated(unsafe) var frame = 0
  
  var isRecording = false

  func start() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: configure()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { ok in
        Task { @MainActor in
          ok
            ? self.configure()
            : (self.unavailable = "Camera access denied. Enable it in Settings → Camera.")
        }
      }
    default: unavailable = "Camera access denied. Enable it in Settings → Camera."
    }
  }

  private func configure() {
    unavailable = nil
    guard session.inputs.isEmpty else {
      queue.async { self.session.startRunning() }
      return
    }
    session.sessionPreset = .medium  // 480p — much lighter than .high for face tracking
    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
    else {
      unavailable = "No camera found. The Simulator has no camera — run on a real iPhone."
      return
    }
    session.addInput(input)
    let output = AVCaptureVideoDataOutput()
    output.setSampleBufferDelegate(self, queue: queue)
    output.alwaysDiscardsLateVideoFrames = true
    if session.canAddOutput(output) { session.addOutput(output) }
    queue.async { self.session.startRunning() }
  }

  func stop() { session.stopRunning() }

  nonisolated func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    frame += 1

    // Skip 2 out of 3 frames to reduce CPU load
    guard frame % 3 == 0 else { return }

    var out: [LiveBox] = []

    if tracks.isEmpty || frame % 30 == 0 {
      // Re-detect every 30 frames (instead of 20) — tracker carries between
      let req = VNDetectFaceRectanglesRequest()
      try? VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .leftMirrored).perform([req])
      let prev = tracks
      var next: [TrackedFace] = []
      for obs in (req.results ?? []) {
        let box = obs.boundingBox
        let center = CGPoint(x: box.midX, y: box.midY)
        let tf = TrackedFace(box: box)
        if let carried = prev.first(where: { $0.box.contains(center) }), carried.name != nil {
          tf.register = carried.register
          tf.name = carried.name
          tf.present = carried.present
          tf.score = carried.score
        } else if let fp = FaceRecognizer.shared.featurePrint(pixelBuffer: pixel, faceBox: box) {
          switch FaceRecognizer.shared.match(fp) {
          case .present(let r, let n, let score):
            tf.register = r
            tf.name = n
            tf.present = true
            tf.score = score
          case .review(let r, let n, let score):
            tf.register = r
            tf.name = n
            tf.present = false
            tf.score = score
          case .none: break
          }
        }
        next.append(tf)
      }
      
      // Enforce uniqueness: if two boxes have the SAME register, keep the highest score.
      var bestScoreForReg: [String: Float] = [:]
      for tf in next {
          if let reg = tf.register {
              bestScoreForReg[reg] = max(bestScoreForReg[reg] ?? -Float.greatestFiniteMagnitude, tf.score)
          }
      }
      for tf in next {
          if let reg = tf.register, tf.score < bestScoreForReg[reg]! {
              tf.register = nil
              tf.name = nil
              tf.present = false
              tf.score = 0
          }
          out.append(LiveBox(rect: tf.box, name: tf.name, present: tf.present))
      }
      
      tracks = next
    } else {
      try? sequence.perform(tracks.map { $0.request }, on: pixel, orientation: .leftMirrored)
      var kept: [TrackedFace] = []
      for tf in tracks {
        if let r = tf.request.results?.first as? VNDetectedObjectObservation, r.confidence > 0.3 {
          tf.request.inputObservation = r
          tf.box = r.boundingBox
          kept.append(tf)
          out.append(LiveBox(rect: tf.box, name: tf.name, present: tf.present))
        }
      }
      tracks = kept
    }

    // Only push UI updates every 2nd processed frame (every 6th real frame) to reduce main thread pressure
    let boxesOut = out
    let present = tracks.compactMap { $0.present ? $0.register : nil }
    if frame % 6 == 0 {
      Task { @MainActor in
        self.boxes = boxesOut
        if self.isRecording {
          present.forEach { self.presentRegisters.insert($0) }
        }
      }
    } else {
      // Still accumulate present registers even if we don't update boxes
      if !present.isEmpty {
        Task { @MainActor in
          if self.isRecording {
            present.forEach { self.presentRegisters.insert($0) }
          }
        }
      }
    }
  }
}

/// Camera preview + named boxes, drawn via the preview layer's own coordinate
/// conversion so they line up regardless of aspect-fill / mirroring.
struct FaceCameraView: UIViewRepresentable {
  @ObservedObject var tracker: FaceTracker

  func makeUIView(context: Context) -> PreviewView {
    let v = PreviewView()
    v.previewLayer.session = tracker.session
    v.previewLayer.videoGravity = .resizeAspectFill
    return v
  }
  func updateUIView(_ v: PreviewView, context: Context) { v.render(tracker.boxes) }

  final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var overlays: [CALayer] = []

    func render(_ boxes: [LiveBox]) {
      // Batch: remove old, add new
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      overlays.forEach { $0.removeFromSuperlayer() }
      overlays.removeAll(keepingCapacity: true)
      let layerSize = previewLayer.bounds.size
      guard layerSize.width > 0, layerSize.height > 0 else {
          CATransaction.commit()
          return
      }
      let imageRatio: CGFloat = 3.0 / 4.0 // 480x640 in portrait
      let viewRatio = layerSize.width / layerSize.height
      
      let scale: CGFloat
      if viewRatio > imageRatio {
          scale = layerSize.width / imageRatio
      } else {
          scale = layerSize.height
      }
      
      let renderedWidth = scale * imageRatio
      let renderedHeight = scale
      
      let xOffset = (layerSize.width - renderedWidth) / 2
      let yOffset = (layerSize.height - renderedHeight) / 2

      for b in boxes {
        let uiY = 1 - b.rect.maxY
        let rect = CGRect(
            x: (b.rect.minX * renderedWidth) + xOffset,
            y: (uiY * renderedHeight) + yOffset,
            width: b.rect.width * renderedWidth,
            height: b.rect.height * renderedHeight
        )
        let color: UIColor =
          b.present ? .systemGreen : (b.name != nil ? .systemOrange : .systemYellow)

        let box = CAShapeLayer()
        box.path = UIBezierPath(roundedRect: rect, cornerRadius: 8).cgPath
        box.strokeColor = color.cgColor
        box.lineWidth = 3
        box.fillColor = UIColor.clear.cgColor
        previewLayer.addSublayer(box)
        overlays.append(box)

        let label = CATextLayer()
        if b.present {
            label.string = b.name ?? "Unknown"
        } else if b.name != nil {
            label.string = "Hard to detect"
        } else {
            label.string = "Not enrolled"
        }
        label.fontSize = 13
        label.foregroundColor = UIColor.white.cgColor
        label.backgroundColor = color.cgColor
        label.alignmentMode = .center
        label.contentsScale = UIScreen.main.scale
        label.frame = CGRect(
          x: rect.minX, y: max(0, rect.minY - 20),
          width: max(80, rect.width), height: 20)
        previewLayer.addSublayer(label)
        overlays.append(label)
      }
      CATransaction.commit()
    }
  }
}

/// Live capture: point the camera, tap Start, a 10-second countdown runs while it
/// recognises + tracks everyone, then shows a summary with Submit/Capture Again.
struct LiveCaptureView: View {
  @ObservedObject var tracker: FaceTracker
  var seconds = 10
  var onComplete: (Set<String>) -> Void

  @State private var countdown = 0
  @State private var running = false
  @State private var finished = false

  var body: some View {
    ZStack {
      if let msg = tracker.unavailable {
        Color(.secondarySystemBackground).ignoresSafeArea()
        VStack(spacing: 10) {
          Image(systemName: "camera.metering.unknown").font(.system(size: 40))
            .foregroundStyle(.secondary)
          Text(msg).font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).padding(.horizontal, 40)
          Button("Skip (use demo)") { onComplete([]) }.padding(.top, 6)
        }
      } else {
        FaceCameraView(tracker: tracker).ignoresSafeArea()
        VStack {
          if running && !finished {
            Text("\(countdown)")
              .font(.system(size: 72, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .padding(.horizontal, 30).padding(.vertical, 8)
              .background(.ultraThinMaterial, in: Capsule())
              .padding(.top, 60).contentTransition(.numericText())
          }
          Spacer()
          Label(
            "\(tracker.presentRegisters.count) present · tracking \(tracker.boxes.count)",
            systemImage: "viewfinder"
          )
          .font(.subheadline.bold())
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(.ultraThinMaterial, in: Capsule())

          if finished {
            // Post-capture: Submit or Capture Again
            VStack(spacing: 12) {
              Text("Capture complete")
                .font(.headline).foregroundStyle(.white)
              Text(
                "\(tracker.presentRegisters.count) student\(tracker.presentRegisters.count == 1 ? "" : "s") detected"
              )
              .font(.subheadline).foregroundStyle(.white.opacity(0.8))
              HStack(spacing: 16) {
                Button {
                  // Reset for another capture round
                  finished = false
                  running = false
                } label: {
                  Label("Add Another Shot", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                Button {
                  onComplete(tracker.presentRegisters)
                } label: {
                  Label("Submit", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Theme.present, in: Capsule())
                }
              }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding()
          } else if !running {
            Button {
              start()
            } label: {
              Label("Start attendance (\(seconds)s)", systemImage: "play.fill")
            }
            .buttonStyle(FilledButton()).padding()
          }
        }
      }
    }
    .onAppear { tracker.start() }
    .onDisappear { tracker.stop() }
  }

  private func start() {
    tracker.isRecording = true
    running = true
    finished = false
    Task {
      for t in stride(from: seconds, through: 1, by: -1) {
        withAnimation { countdown = t }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
      withAnimation { finished = true }
      tracker.isRecording = false
    }
  }
}
