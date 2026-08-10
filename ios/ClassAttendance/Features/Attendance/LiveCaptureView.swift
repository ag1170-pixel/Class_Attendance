import SwiftUI
import AVFoundation
import Vision

/// On-device live capture for "Take Attendance": shows the camera, detects faces
/// with Vision, and TRACKS each face across frames (recognise-once-then-track) so
/// a mask or a turned head doesn't drop the box. Runs fully on-device.
/// Identity matching (who each face is) is the next milestone (Core ML embedding).
@MainActor
final class FaceTracker: NSObject, ObservableObject,
                         AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var boxes: [CGRect] = []      // normalized Vision rects (origin bottom-left)
    @Published var count = 0
    @Published var unavailable: String?

    private let queue = DispatchQueue(label: "face.tracker")
    private let sequence = VNSequenceRequestHandler()
    // Touched only on the serial capture queue, so single-threaded access is safe.
    private nonisolated(unsafe) var trackers: [VNTrackObjectRequest] = []
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
        var rects: [CGRect] = []

        if trackers.isEmpty || frame % 20 == 0 {
            // Re-detect to pick up new faces / re-seed trackers.
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .leftMirrored).perform([req])
            let faces = req.results ?? []
            trackers = faces.map {
                VNTrackObjectRequest(detectedObjectObservation:
                    VNDetectedObjectObservation(boundingBox: $0.boundingBox))
            }
            rects = faces.map { $0.boundingBox }
        } else {
            // Track existing faces (survives mask / turned head).
            try? sequence.perform(trackers, on: pixel, orientation: .leftMirrored)
            var kept: [VNTrackObjectRequest] = []
            for t in trackers {
                if let r = t.results?.first as? VNDetectedObjectObservation, r.confidence > 0.3 {
                    t.inputObservation = r
                    kept.append(t)
                    rects.append(r.boundingBox)
                }
            }
            trackers = kept
        }

        let out = rects
        Task { @MainActor in self.boxes = out; self.count = out.count }
    }
}

/// Camera preview + tracked-face boxes, drawn with the preview layer's own
/// coordinate conversion so they line up regardless of aspect-fill / mirroring.
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
        private var boxLayers: [CAShapeLayer] = []

        func render(_ visionBoxes: [CGRect]) {
            boxLayers.forEach { $0.removeFromSuperlayer() }
            boxLayers = visionBoxes.map { vb in
                // Vision (bottom-left) -> metadata (top-left) -> layer coordinates.
                let meta = CGRect(x: vb.minX, y: 1 - vb.maxY, width: vb.width, height: vb.height)
                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: meta)
                let l = CAShapeLayer()
                l.path = UIBezierPath(roundedRect: rect, cornerRadius: 8).cgPath
                l.strokeColor = UIColor.systemGreen.cgColor
                l.lineWidth = 3
                l.fillColor = UIColor.clear.cgColor
                previewLayer.addSublayer(l)
                return l
            }
        }
    }
}

/// Live capture shown during the ~5-second attendance window.
struct LiveCaptureView: View {
    @StateObject private var tracker = FaceTracker()

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
                    Label("Recognising… tracking \(tracker.count) face\(tracker.count == 1 ? "" : "s")",
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
