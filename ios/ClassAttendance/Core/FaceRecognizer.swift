import Foundation
import Vision
import CoreImage

/// On-device face recognition — no server, no model download.
///
/// v1 uses Vision's `VNGenerateImageFeaturePrintRequest` (Neural Engine) as the
/// face embedding: enrol a face once, then match live faces by feature-print
/// distance with the same dual-threshold rule as the server (docs/06_ACCURACY.md).
/// Distance is the inverse of similarity — smaller = closer. Thresholds need a
/// quick on-device tune per device/lighting.
///
/// Upgrade path (max accuracy): drop a converted ArcFace/FaceNet Core ML model
/// behind `featurePrint(...)` — the enrol/match flow is unchanged.
///
/// Thread-safe: `featurePrint`/`match` are called from the camera queue;
/// `enroll` from the main thread. A lock guards the enrolled set.
final class FaceRecognizer {
    static let shared = FaceRecognizer()

    // Tune on-device: below `present` = confident; below `review` = surface to teacher.
    var distPresent: Float = 0.6
    var distReview: Float = 0.9

    struct Enrolled { let register: String; let name: String; var prints: [VNFeaturePrintObservation] }
    enum Result { case present(String, String), review(String, String), none }

    private var enrolled: [String: Enrolled] = [:]   // keyed by register
    private let lock = NSLock()
    private let store = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("enroll.json")

    init() { load() }

    var count: Int { lock.lock(); defer { lock.unlock() }; return enrolled.count }

    // MARK: embedding (pure; safe on any thread)

    /// Feature print for the face region of a pixel buffer (Vision bbox, bottom-left).
    func featurePrint(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> VNFeaturePrintObservation? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let px = VNImageRectForNormalizedRect(faceBox, Int(ci.extent.width), Int(ci.extent.height))
            .insetBy(dx: -20, dy: -20)                 // a little context around the face
        let crop = ci.cropped(to: px.intersection(ci.extent))
        guard !crop.extent.isEmpty else { return nil }
        let req = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(ciImage: crop).perform([req])
        return req.results?.first as? VNFeaturePrintObservation
    }

    // MARK: enrol

    func enroll(register: String, name: String, print: VNFeaturePrintObservation) {
        lock.lock()
        var e = enrolled[register] ?? Enrolled(register: register, name: name, prints: [])
        e = Enrolled(register: register, name: name, prints: e.prints + [print])
        enrolled[register] = e
        saveLocked()
        lock.unlock()
    }

    // MARK: match (dual-threshold)

    func match(_ probe: VNFeaturePrintObservation) -> Result {
        lock.lock(); let snapshot = Array(enrolled.values); lock.unlock()
        var bestReg = "", bestName = "", best = Float.greatestFiniteMagnitude
        for e in snapshot {
            for p in e.prints {
                var d = Float.greatestFiniteMagnitude
                try? p.computeDistance(&d, to: probe)
                if d < best { best = d; bestReg = e.register; bestName = e.name }
            }
        }
        if best <= distPresent { return .present(bestReg, bestName) }
        if best <= distReview  { return .review(bestReg, bestName) }
        return .none
    }

    // MARK: persistence (feature prints are NSSecureCoding)

    private struct Row: Codable { let register: String; let name: String; let prints: [Data] }

    private func saveLocked() {
        let rows = enrolled.values.map { e in
            Row(register: e.register, name: e.name,
                prints: e.prints.compactMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                })
        }
        if let data = try? JSONEncoder().encode(rows) { try? data.write(to: store) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: store),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }
        for r in rows {
            let prints = r.prints.compactMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: $0)
            }
            if !prints.isEmpty { enrolled[r.register] = Enrolled(register: r.register, name: r.name, prints: prints) }
        }
    }
}
