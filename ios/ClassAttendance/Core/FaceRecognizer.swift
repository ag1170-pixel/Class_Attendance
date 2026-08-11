import Foundation
import Vision
import CoreImage

/// On-device face recognition — purely Apple-native, no external model required!
///
/// v2: Uses Vision's `VNGenerateImageFeaturePrintRequest` but fixes the previous 
/// false-positive bug by applying a STRICT crop to the face bounding box, completely
/// eliminating the background from the feature print.
final class FaceRecognizer {
    static let shared = FaceRecognizer()

    // Distance thresholds (lower is closer/better match)
    // We will convert distance to a "score" by negating it, so higher score is better.
    var distPresent: Float = 10.0
    var distReview: Float = 15.0

    struct Enrolled { let register: String; let name: String; var prints: [VNFeaturePrintObservation] }
    
    // Result includes the score (which is -distance, so closer to 0 is better, -15 is worse)
    enum Result { case present(String, String, Float), review(String, String, Float), none }

    private var enrolled: [String: Enrolled] = [:]   // keyed by register
    private let lock = NSLock()
    private let store = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("enroll_native.json")

    init() { load() }

    var count: Int { lock.lock(); defer { lock.unlock() }; return enrolled.count }

    // MARK: embedding

    func featurePrint(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> VNFeaturePrintObservation? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        // STRICT CROP: We do NOT inset or expand the box. We only want the face pixels.
        let px = VNImageRectForNormalizedRect(faceBox, Int(ci.extent.width), Int(ci.extent.height))
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
    
    func delete(register: String) {
        lock.lock()
        enrolled.removeValue(forKey: register)
        saveLocked()
        lock.unlock()
    }
    
    func deleteAll() {
        lock.lock()
        enrolled.removeAll()
        saveLocked()
        lock.unlock()
    }
    
    func enrolledList() -> [(register: String, name: String)] {
        lock.lock()
        defer { lock.unlock() }
        return enrolled.values.map { (register: $0.register, name: $0.name) }.sorted { $0.name < $1.name }
    }

    // MARK: match

    func match(_ probe: VNFeaturePrintObservation) -> Result {
        lock.lock(); let snapshot = Array(enrolled.values); lock.unlock()
        var bestReg = "", bestName = "", bestDist = Float.greatestFiniteMagnitude
        
        for e in snapshot {
            for p in e.prints {
                var d = Float.greatestFiniteMagnitude
                try? p.computeDistance(&d, to: probe)
                if d < bestDist { bestDist = d; bestReg = e.register; bestName = e.name }
            }
        }
        
        let score = -bestDist // Convert distance to score so higher is better
        
        if bestDist <= distPresent { return .present(bestReg, bestName, score) }
        if bestDist <= distReview  { return .review(bestReg, bestName, score) }
        return .none
    }

    // MARK: persistence

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
