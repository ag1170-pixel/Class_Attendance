import SwiftUI
import AVFoundation
import Vision

/// One-time face enrollment (the "scan once" step). Runs the camera and uses the
/// Vision framework ON-DEVICE to gate capture on face quality — the app only
/// accepts a frame with a single, well-captured face. The accepted crop is sent
/// to the backend for embedding + consent-gated storage.
///
/// Requires Info.plist: NSCameraUsageDescription.
struct EnrollmentView: View {
    @StateObject private var cam = FaceCaptureController()
    @State private var registerNo = ""
    @State private var fullName = ""
    @State private var consent = false

    var body: some View {
        Form {
            Section("Student") {
                TextField("Register No", text: $registerNo)
                TextField("Full name", text: $fullName)
            }
            Section("Consent") {
                Toggle("Student consents to face enrollment", isOn: $consent)
                    .tint(.green)
                Text("Biometric data is stored by the university, encrypted, and can be revoked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Capture") {
                CameraPreview(session: cam.session)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Label(cam.quality.message, systemImage: cam.quality.symbol)
                    .foregroundStyle(cam.quality.isReady ? .green : .orange)
            }
            Button("Enroll Face") { /* POST crop + consent to backend */ }
                .disabled(!(consent && cam.quality.isReady
                            && !registerNo.isEmpty && !fullName.isEmpty))
        }
        .navigationTitle("Enroll Student")
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
    }
}

/// Live face-quality gate using Vision. Publishes a simple readiness state.
@MainActor
final class FaceCaptureController: NSObject, ObservableObject,
                                   AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Quality {
        var isReady = false
        var message = "Point the camera at the student's face"
        var symbol = "viewfinder"
    }

    let session = AVCaptureSession()
    @Published var quality = Quality()
    private let queue = DispatchQueue(label: "face.capture")

    func start() {
        guard session.inputs.isEmpty else { session.startRunning(); return }
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        queue.async { self.session.startRunning() }
    }

    func stop() { session.stopRunning() }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceCaptureQualityRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixel).perform([request])
        let faces = (request.results ?? [])
        Task { @MainActor in self.evaluate(faces) }
    }

    @MainActor
    private func evaluate(_ faces: [VNFaceObservation]) {
        if faces.isEmpty {
            quality = Quality(isReady: false,
                              message: "No face detected", symbol: "viewfinder")
        } else if faces.count > 1 {
            quality = Quality(isReady: false,
                              message: "Multiple faces — one student at a time",
                              symbol: "person.2.slash")
        } else if (faces[0].faceCaptureQuality ?? 0) < 0.5 {
            quality = Quality(isReady: false,
                              message: "Hold steady, get closer",
                              symbol: "camera.metering.center.weighted")
        } else {
            quality = Quality(isReady: true,
                              message: "Good — ready to enroll",
                              symbol: "checkmark.circle.fill")
        }
    }
}

/// Minimal UIKit bridge for the camera preview layer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer.session = session
        v.layer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}
