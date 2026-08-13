import SwiftUI
import AVFoundation
import Vision
import CoreImage

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
    @State private var captured: [[Float]] = []      // the 3 face embeddings
    @State private var thumbs: [UIImage] = []         // matching thumbnails
    @State private var showSuccess = false
    @State private var enrolledList: [(register: String, name: String)] = []
    @FocusState private var isInputActive: Bool

    private let need = 3   // require 3 photos for reliable recognition
    @State private var firstTurnSign: Double = 0   // remembers which way they turned for shot 2

    private let stepHints = ["Look straight at the camera",
                             "Turn your head slightly to one side",
                             "Now turn slightly the other way"]

    var isDuplicate: Bool { enrolledList.contains(where: { $0.register == registerNo }) }

    var canEnroll: Bool {
        captured.count == need && consent && !registerNo.isEmpty && !fullName.isEmpty && !isDuplicate
    }

    /// Is the head pose right for the current shot? (frontal, then two opposite turns.)
    /// If Vision can't read the angle, we don't block — quality still gates capture.
    private func poseOK() -> Bool {
        guard let y = cam.yaw else { return true }
        switch captured.count {
        case 0:  return abs(y) <= 0.22                                   // frontal
        case 1:  return abs(y) >= 0.11                                   // turned either way
        default: return abs(y) >= 0.11 && (firstTurnSign == 0 || y * firstTurnSign < 0)  // opposite side
        }
    }

    private var readyToCapture: Bool {
        cam.unavailable == nil && cam.quality.isReady && poseOK()
    }

    var body: some View {
        Form {
            Section("Student") {
                TextField("Register No", text: $registerNo)
                    .focused($isInputActive).textInputAutocapitalization(.characters)
                TextField("Full name", text: $fullName)
                    .focused($isInputActive)
            }
            Section("Consent") {
                Toggle("Student consents to face enrollment", isOn: $consent)
                    .tint(.green)
                Text("Biometric data is stored by the university, encrypted, and can be revoked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Capture \(need) photos") {
                ZStack {
                    CameraPreview(session: cam.session)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if cam.unavailable == nil && captured.count < need {
                        PoseGuideOverlay(step: captured.count, ready: readyToCapture)
                            .frame(height: 260).allowsHitTesting(false)
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
                    // Progress: 3 thumbnail slots + counter.
                    HStack(spacing: 10) {
                        ForEach(0..<need, id: \.self) { i in
                            if i < thumbs.count {
                                Image(uiImage: thumbs[i]).resizable().scaledToFill()
                                    .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.present, lineWidth: 2))
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(Theme.surface2)
                                    .frame(width: 46, height: 46)
                                    .overlay(Image(systemName: "plus").foregroundStyle(Theme.dim))
                            }
                        }
                        Spacer()
                        Text("\(captured.count)/\(need)")
                            .font(.headline).monospacedDigit()
                            .foregroundStyle(captured.count == need ? Theme.present : Theme.dim)
                    }
                    if captured.count < need {
                        Text(stepHints[captured.count]).font(.subheadline.bold())
                        Label(readyToCapture ? "Hold still — ready to capture"
                                             : (poseOK() ? cam.quality.message : "Match the pose above"),
                              systemImage: readyToCapture ? "checkmark.circle.fill" : cam.quality.symbol)
                            .foregroundStyle(readyToCapture ? .green : .orange)
                        Button {
                            if let s = cam.grabSample() {
                                if captured.count == 1 { firstTurnSign = (cam.yaw ?? 0) >= 0 ? 1 : -1 }
                                captured.append(s.0); thumbs.append(s.1)
                            }
                        } label: {
                            Label("Capture \(captured.count + 1) of \(need)", systemImage: "camera.shutter.button")
                        }
                        .buttonStyle(.borderedProminent).disabled(!readyToCapture)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.present)
                            Text("\(need) photos captured — ready to enroll")
                            Spacer()
                            Button("Retake") { captured.removeAll(); thumbs.removeAll() }
                                .font(.subheadline).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }

            if isDuplicate {
                Text("This Register No is already enrolled. Delete it below to re-enroll.")
                    .font(.footnote).foregroundStyle(.red)
            }

            Button(showSuccess ? "Enrolled ✓" : "Enroll Face") {
                for print in captured {
                    FaceRecognizer.shared.enroll(register: registerNo, name: fullName, print: print)
                }
                showSuccess = true
                enrolledList = FaceRecognizer.shared.enrolledList()
                captured.removeAll(); thumbs.removeAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    showSuccess = false; registerNo = ""; fullName = ""; consent = false
                }
            }
            .disabled(showSuccess || !canEnroll)

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
    @Published var yaw: Double?          // head turn (radians): ~0 = straight, ± = turned
    private let queue = DispatchQueue(label: "face.capture")
    // Latest good face embedding, kept ready for the Enroll button.
    private nonisolated(unsafe) var latestPrint: [Float]?
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

    /// Grab the current good face: its embedding + a thumbnail (nil if no good frame).
    /// Uses the SAME .leftMirrored orientation as recognition so enrolled and live
    /// embeddings line up.
    func grabSample() -> ([Float], UIImage)? {
        guard let p = latestPrint, let pb = latestPixelBuffer else { return nil }
        let ci = CIImage(cvPixelBuffer: pb).oriented(.leftMirrored)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return (p, UIImage()) }
        return (p, UIImage(cgImage: cg))
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
        let quality = VNDetectFaceCaptureQualityRequest()
        let rect = VNDetectFaceRectanglesRequest()   // gives head yaw for pose guidance
        // Same orientation as the live recogniser (.leftMirrored front camera) so the
        // enrolled embedding is aligned identically to what attendance compares against.
        try? VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .leftMirrored)
            .perform([quality, rect])
        let faces = (quality.results ?? [])
        let yawVal = rect.results?.first?.yaw?.doubleValue
        if faces.count == 1, (faces[0].faceCaptureQuality ?? 0) >= 0.35 {
            latestPixelBuffer = pixel
            latestPrint = FaceRecognizer.shared.featurePrint(pixelBuffer: pixel, faceBox: faces[0].boundingBox,
                                                             orientation: .leftMirrored)
        }
        Task { @MainActor in self.yaw = yawVal; self.evaluate(faces) }
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
/// Semi-transparent animated guide: a pulsing face oval + turn arrows telling the
/// user how to pose for each enrollment shot. Turns green when the pose is right.
struct PoseGuideOverlay: View {
    let step: Int          // 0 = look straight, 1 & 2 = turn
    let ready: Bool
    @State private var pulse = false
    @State private var slide = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.10)

            Ellipse()
                .strokeBorder(ready ? Color.green : Color.white.opacity(0.85),
                              style: StrokeStyle(lineWidth: 3, dash: [9, 7]))
                .frame(width: 150, height: 195)
                .scaleEffect(pulse ? 1.03 : 1.0)
                .shadow(color: ready ? Color.green.opacity(0.7) : .clear, radius: 8)

            if step >= 1 {
                // Two chevrons sliding side-to-side = "turn your head".
                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 226)
                .offset(x: slide ? 12 : -12)
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: 24)).foregroundStyle(.white.opacity(0.75))
                    .offset(y: 58)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { slide = true }
        }
    }
}

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
