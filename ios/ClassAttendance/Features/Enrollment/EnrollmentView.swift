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
    @State private var enrollCount = 0
    @State private var showSuccess = false
    @State private var enrolledList: [(register: String, name: String)] = []
    @FocusState private var isInputActive: Bool
    
    var isDuplicate: Bool {
        enrollCount == 0 && enrolledList.contains(where: { $0.register == registerNo })
    }

    var body: some View {
        Form {
            Section("Student") {
                TextField("Register No", text: $registerNo)
                    .focused($isInputActive)
                TextField("Full name", text: $fullName)
                    .focused($isInputActive)
            }
            Section("Consent") {
                Toggle("Student consents to face enrollment", isOn: $consent)
                    .tint(.green)
                Text("Biometric data is stored by the university, encrypted, and can be revoked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Capture") {
                ZStack {
                    if let frozen = cam.frozenImage {
                        // Show frozen captured frame
                        Image(uiImage: frozen)
                            .resizable().scaledToFill()
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        CameraPreview(session: cam.session)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let msg = cam.unavailable {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.surface2).frame(height: 260)
                        VStack(spacing: 8) {
                            Image(systemName: "camera.metering.unknown").font(.system(size: 34))
                                .foregroundStyle(Theme.dim)
                            Text(msg).font(.footnote).foregroundStyle(Theme.dim)
                                .multilineTextAlignment(.center).padding(.horizontal)
                        }
                    }
                }
                if cam.unavailable == nil {
                    if cam.frozenImage != nil {
                        // Frozen state — show confirm/retake
                        HStack {
                            Button { cam.unfreeze() } label: {
                                Label("Retake", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Label("Ready to enroll", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        // Live state — show quality + capture button
                        Label(cam.quality.message, systemImage: cam.quality.symbol)
                            .foregroundStyle(cam.quality.isReady ? .green : .orange)
                        if cam.quality.isReady {
                            Button { cam.freeze() } label: {
                                Label("Capture Photo", systemImage: "camera.shutter.button")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            if enrollCount > 0 {
                Section("Enrolled Photos") {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.present)
                        Text("\(enrollCount) photo\(enrollCount == 1 ? "" : "s") enrolled")
                        Spacer()
                        Button("Add Another") {
                            cam.unfreeze()
                        }
                        .font(.subheadline).foregroundStyle(Theme.accent)
                    }
                }
            }

            if isDuplicate {
                Text("This Register No is already enrolled. Delete it from the list below if you want to re-enroll.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(showSuccess ? "Enrolled ✓" : (enrollCount > 0 ? "Add This Photo" : "Enroll Face")) {
                if cam.enroll(register: registerNo, name: fullName) {
                    enrollCount += 1
                    showSuccess = true
                    // Auto-unfreeze after a moment so they can add more
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showSuccess = false
                    }
                    enrolledList = FaceRecognizer.shared.enrolledList()
                }
            }
            .disabled(showSuccess || cam.frozenImage == nil || isDuplicate
                      || !(consent && !registerNo.isEmpty && !fullName.isEmpty))
            
            if !enrolledList.isEmpty {
                Section("All Enrolled Students") {
                    ForEach(enrolledList, id: \.register) { student in
                        VStack(alignment: .leading) {
                            Text(student.name)
                            Text(student.register).font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            FaceRecognizer.shared.delete(register: enrolledList[i].register)
                        }
                        enrolledList = FaceRecognizer.shared.enrolledList()
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        FaceRecognizer.shared.deleteAll()
                        enrolledList = []
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete All Face Data")
                            Spacer()
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputActive = false
                }
            }
        }
        .navigationTitle("Enroll Student")
        .onAppear {
            cam.start()
            enrolledList = FaceRecognizer.shared.enrolledList()
        }
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
    @Published var unavailable: String?
    @Published var frozenImage: UIImage?
    private let queue = DispatchQueue(label: "face.capture")
    // Latest good face embedding, kept ready for the Enroll button.
    private nonisolated(unsafe) var latestPrint: VNFeaturePrintObservation?
    private nonisolated(unsafe) var latestPixelBuffer: CVPixelBuffer?
    private nonisolated(unsafe) var frameCount: Int = 0

    /// Freeze the current frame for review before enrolling
    func freeze() {
        guard let pb = latestPixelBuffer else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        let ctx = CIContext()
        if let cg = ctx.createCGImage(ci, from: ci.extent) {
            frozenImage = UIImage(cgImage: cg)
        }
    }

    /// Unfreeze to go back to live camera
    func unfreeze() {
        frozenImage = nil
    }

    /// Store the last good face under this student. Returns false if no good frame yet.
    func enroll(register: String, name: String) -> Bool {
        guard let p = latestPrint else { return false }
        FaceRecognizer.shared.enroll(register: register, name: name, print: p)
        return true
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    granted ? self.configure()
                            : (self.unavailable = "Camera access denied. Enable it in Settings → Camera.")
                }
            }
        default:
            unavailable = "Camera access denied. Enable it in Settings → Camera."
        }
    }

    private func configure() {
        unavailable = nil
        guard session.inputs.isEmpty else { queue.async { self.session.startRunning() }; return }
        session.sessionPreset = .medium        // 480p — much lighter than .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
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

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        frameCount += 1
        // Skip frames to reduce CPU load — process every 3rd frame
        guard frameCount % 3 == 0 else { return }

        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceCaptureQualityRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixel).perform([request])
        let faces = (request.results ?? [])
        if faces.count == 1, (faces[0].faceCaptureQuality ?? 0) >= 0.35 {
            latestPixelBuffer = pixel
            latestPrint = FaceRecognizer.shared.featurePrint(pixelBuffer: pixel, faceBox: faces[0].boundingBox)
        }
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
        } else if (faces[0].faceCaptureQuality ?? 0) < 0.35 {
            quality = Quality(isReady: false,
                              message: "Hold steady, get closer",
                              symbol: "camera.metering.center.weighted")
        } else {
            quality = Quality(isReady: true,
                              message: "Ready to enroll", symbol: "checkmark.circle")
        }
    }
}

/// Minimal UIKit bridge for the camera preview layer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
