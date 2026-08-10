import SwiftUI
import AVFoundation
import Vision

/// One tracked person on screen: a Vision object tracker + the identity bound to
/// them (recognise once, then the tracker carries it through masks/turns).
final class TrackedFace {
    var request: VNTrackObjectRequest
    var box: CGRect
    var register: String?
    var name: String?
    var present = false            // matched at the "present" threshold
    init(box: CGRect) {
        self.box = box
        request = VNTrackObjectRequest(detectedObjectObservation:
            VNDetectedObjectObservation(boundingBox: box))
    }
}

struct LiveBox { let rect: CGRect; let name: String?; let present: Bool }

/// On-device live capture: detect + track faces, recognise each ONCE (Vision
/// feature print → FaceRecognizer), then the tracker follows them. Publishes the
/// boxes and the set of register numbers seen present. Fully on-device.
@MainActor
final class FaceTracker: NSObject, ObservableObject,
                         AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var boxes: [LiveBox] = []
    @Published var presentRegisters: Set<String> = []
    @Published var unavailable: String?

    private let queue = DispatchQueue(label: "face.tracker")
    private let sequence = VNSequenceRequestHandler()
    private nonisolated(unsafe) var tracks: [TrackedFace] = []   // capture-queue only
    private nonisolated(unsafe) var frame = 0

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in ok ? self.configure()
                    : (self.unavailable = "Camera access denied. Enable it in Settings → Camera.") }
            }
        default: unavailable = "Camera access denied. Enable it in Settings → Camera."
        }
    }

    private func configure() {
        unavailable = nil
        guard session.inputs.isEmpty else { queue.async { self.session.startRunning() }; return }
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            unavailable = "No camera found. The Simulator has no camera — run on a real iPhone."
            return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        queue.async { self.session.startRunning() }
    }

    func stop() { session.stopRunning() }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frame += 1
        var out: [LiveBox] = []

        if tracks.isEmpty || frame % 20 == 0 {
            // Re-detect; carry identity from a previous track under the same spot,
            // otherwise recognise this face once.
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .leftMirrored).perform([req])
            let prev = tracks
            var next: [TrackedFace] = []
            for obs in (req.results ?? []) {
                let box = obs.boundingBox
                let center = CGPoint(x: box.midX, y: box.midY)
                let tf = TrackedFace(box: box)
                if let carried = prev.first(where: { $0.box.contains(center) }), carried.name != nil {
                    tf.register = carried.register; tf.name = carried.name; tf.present = carried.present
                } else if let fp = FaceRecognizer.shared.featurePrint(pixelBuffer: pixel, faceBox: box) {
                    switch FaceRecognizer.shared.match(fp) {
                    case .present(let r, let n): tf.register = r; tf.name = n; tf.present = true
                    case .review(let r, let n):  tf.register = r; tf.name = n; tf.present = false
                    case .none: break
                    }
                }
                next.append(tf)
                out.append(LiveBox(rect: box, name: tf.name, present: tf.present))
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

        let boxesOut = out
        let present = tracks.compactMap { $0.present ? $0.register : nil }
        Task { @MainActor in
            self.boxes = boxesOut
            present.forEach { self.presentRegisters.insert($0) }
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
            overlays.forEach { $0.removeFromSuperlayer() }
            overlays = []
            for b in boxes {
                let meta = CGRect(x: b.rect.minX, y: 1 - b.rect.maxY, width: b.rect.width, height: b.rect.height)
                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: meta)
                let color: UIColor = b.present ? .systemGreen : (b.name != nil ? .systemOrange : .systemYellow)

                let box = CAShapeLayer()
                box.path = UIBezierPath(roundedRect: rect, cornerRadius: 8).cgPath
                box.strokeColor = color.cgColor; box.lineWidth = 3; box.fillColor = UIColor.clear.cgColor
                previewLayer.addSublayer(box); overlays.append(box)

                let label = CATextLayer()
                label.string = b.name ?? "Not enrolled"
                label.fontSize = 13; label.foregroundColor = UIColor.white.cgColor
                label.backgroundColor = color.cgColor; label.alignmentMode = .center
                label.contentsScale = UIScreen.main.scale
                label.frame = CGRect(x: rect.minX, y: max(0, rect.minY - 20),
                                     width: max(80, rect.width), height: 20)
                previewLayer.addSublayer(label); overlays.append(label)
            }
        }
    }
}

/// Live capture shown during the ~5-second attendance window.
struct LiveCaptureView: View {
    @ObservedObject var tracker: FaceTracker

    var body: some View {
        ZStack {
            if let msg = tracker.unavailable {
                Color(.secondarySystemBackground).ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "camera.metering.unknown").font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(msg).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            } else {
                FaceCameraView(tracker: tracker).ignoresSafeArea()
                VStack {
                    Spacer()
                    Label("Recognising… \(tracker.presentRegisters.count) present · tracking \(tracker.boxes.count)",
                          systemImage: "viewfinder")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear { tracker.start() }
        .onDisappear { tracker.stop() }
    }
}
