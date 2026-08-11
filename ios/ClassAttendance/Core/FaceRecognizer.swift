import Foundation
import Vision
import CoreImage
import CoreML

/// On-device face recognition using CoreML (MobileFaceNet).
///
/// Upgraded to use a true facial identity embedding model instead of the generic
/// Apple image feature print. This calculates a 128-d or 512-d vector and uses
/// Cosine Similarity to compare faces, completely ignoring the background!
final class FaceRecognizer {
    static let shared = FaceRecognizer()

    // Cosine similarity thresholds: higher is better (1.0 is exact match)
    var simPresent: Float = 0.65
    var simReview: Float = 0.50

    struct Enrolled { let register: String; let name: String; var prints: [[Float]] }

    private var enrolled: [String: Enrolled] = [:]   // keyed by register
    private let lock = NSLock()
    private let store = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("enroll_coreml.json")

    private var faceModel: VNCoreMLModel?

    init() {
        load()
        // Dynamically load the MobileFaceNet model if the user added it to the Xcode project
        if let modelURL = Bundle.main.url(forResource: "MobileFaceNet", withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: modelURL) {
            self.faceModel = try? VNCoreMLModel(for: model)
        }
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return enrolled.count }

    // MARK: embedding (pure; safe on any thread)

    /// Extracts a facial embedding vector from the cropped face using CoreML.
    func featurePrint(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> [Float]? {
        guard let faceModel = faceModel else {
            print("WARNING: MobileFaceNet.mlmodel not found in bundle!")
            return nil
        }
        
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let px = VNImageRectForNormalizedRect(faceBox, Int(ci.extent.width), Int(ci.extent.height))
        let crop = ci.cropped(to: px.intersection(ci.extent))
        guard !crop.extent.isEmpty else { return nil }
        
        let req = VNCoreMLRequest(model: faceModel)
        // MobileFaceNet usually expects 112x112, Vision scales it automatically
        req.imageCropAndScaleOption = .scaleFill 
        
        try? VNImageRequestHandler(ciImage: crop).perform([req])
        
        guard let results = req.results as? [VNCoreMLFeatureValueObservation],
              let multiArray = results.first?.featureValue.multiArrayValue else { return nil }
        
        var embedding: [Float] = []
        for i in 0..<multiArray.count {
            embedding.append(multiArray[i].floatValue)
        }
        return embedding
    }

    // MARK: enrol

    func enroll(register: String, name: String, print: [Float]) {
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

    // MARK: match (cosine similarity)

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).map(*).reduce(0, +)
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        return magA * magB == 0 ? 0 : dot / (magA * magB)
    }

    enum Result { case present(String, String, Float), review(String, String, Float), none }

    func match(_ probe: [Float]) -> Result {
        lock.lock(); let snapshot = Array(enrolled.values); lock.unlock()
        var bestReg = "", bestName = "", bestSim: Float = -1.0
        
        for e in snapshot {
            for p in e.prints {
                let sim = cosineSimilarity(p, probe)
                if sim > bestSim { bestSim = sim; bestReg = e.register; bestName = e.name }
            }
        }
        
        if bestSim >= simPresent { return .present(bestReg, bestName, bestSim) }
        if bestSim >= simReview  { return .review(bestReg, bestName, bestSim) }
        return .none
    }

    // MARK: persistence

    private struct Row: Codable { let register: String; let name: String; let prints: [[Float]] }

    private func saveLocked() {
        let rows = enrolled.values.map { e in
            Row(register: e.register, name: e.name, prints: e.prints)
        }
        if let data = try? JSONEncoder().encode(rows) { try? data.write(to: store) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: store),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }
        for r in rows {
            if !r.prints.isEmpty { enrolled[r.register] = Enrolled(register: r.register, name: r.name, prints: r.prints) }
        }
    }
}
