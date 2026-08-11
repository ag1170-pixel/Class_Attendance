import Foundation
import Vision
import CoreML
import CoreImage

/// On-device face recognition — purely Apple-native, no external model required!
///
/// v2: Uses VNCoreMLRequest for face embeddings, returning 512-d [Float] 
/// arrays, and evaluates matches using cosine similarity.
final class FaceRecognizer {
    static let shared = FaceRecognizer()

    // Cosine similarity thresholds (higher is better, max 1.0)
    // 0.85 cosine similarity is the threshold for FaceNet without MTCNN
    // meaning the face must be highly aligned and very confident.
    var distPresent: Float = 0.85
    var distReview: Float = 0.80

    struct Enrolled { let register: String; let name: String; var prints: [[Float]] }
    
    // Result includes the score (cosine similarity)
    enum Result { case present(String, String, Float), review(String, String, Float), none }

    private var enrolled: [String: Enrolled] = [:]   // keyed by register
    private let lock = NSLock()
    private let store = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("enroll_facenet.json")
    
    private var coreMLModel: VNCoreMLModel?

    init() { 
        load() 
        setupModel()
    }
    
    // Returns the best score for each enrolled person
    func matchAll(_ probe: [Float]) -> [String: (name: String, score: Float)] {
        lock.lock(); defer { lock.unlock() }
        var results: [String: (name: String, score: Float)] = [:]
        
        for e in enrolled.values {
            var bestScore: Float = -1.0
            for p in e.prints {
                let score = cosineSimilarity(p, probe)
                if score > bestScore {
                    bestScore = score
                }
            }
            results[e.register] = (name: e.name, score: bestScore)
        }
        return results
    }

    private func setupModel() {
        guard let url = Bundle.main.url(forResource: "MobileFaceNet", withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: url),
              let vnModel = try? VNCoreMLModel(for: mlModel) else {
            print("WARNING: MobileFaceNet.mlmodelc not found! Fallback unavailable.")
            return
        }
        self.coreMLModel = vnModel
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return enrolled.count }

    // MARK: embedding

    func featurePrint(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> [Float]? {
        guard let coreMLModel = coreMLModel else { return nil }
        
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let px = VNImageRectForNormalizedRect(faceBox, Int(ci.extent.width), Int(ci.extent.height))
        // Expand the crop slightly to include the full head for FaceNet
        let expanded = px.insetBy(dx: -px.width * 0.1, dy: -px.height * 0.1)
        let crop = ci.cropped(to: expanded.intersection(ci.extent))
        guard !crop.extent.isEmpty else { return nil }
        
        let req = VNCoreMLRequest(model: coreMLModel)
        req.imageCropAndScaleOption = .scaleFill // FaceNet expects 160x160 RGB
        try? VNImageRequestHandler(ciImage: crop).perform([req])
        
        guard let result = req.results?.first as? VNCoreMLFeatureValueObservation,
              let multiArray = result.featureValue.multiArrayValue else { return nil }
              
        // Extract 512-d vector
        var embedding: [Float] = []
        for i in 0..<multiArray.count {
            embedding.append(multiArray[i].floatValue)
        }
        return normalize(embedding)
    }

    // MARK: enrol

    func enroll(register: String, name: String, print: [Float]) {
        lock.lock()
        var e = enrolled[register] ?? Enrolled(register: register, name: name, prints: [])
        e.prints.append(print)
        enrolled[register] = e
        lock.unlock()
        save()
    }

    func enrolledList() -> [(register: String, name: String)] {
        lock.lock(); defer { lock.unlock() }
        return Array(enrolled.values).map { (register: $0.register, name: $0.name) }.sorted(by: { $0.register < $1.register })
    }

    func deleteAll() {
        lock.lock()
        enrolled.removeAll()
        lock.unlock()
        save()
    }
    
    func delete(register: String) {
        lock.lock()
        enrolled.removeValue(forKey: register)
        lock.unlock()
        save()
    }

    // MARK: match

    func match(_ probe: [Float]) -> Result {
        lock.lock(); defer { lock.unlock() }
        var bestScore: Float = -1.0
        var bestReg: String?
        var bestName: String?

        for e in enrolled.values {
            for p in e.prints {
                let score = cosineSimilarity(p, probe)
                if score > bestScore {
                    bestScore = score
                    bestReg = e.register
                    bestName = e.name
                }
            }
        }
        guard let r = bestReg, let n = bestName else { return .none }
        if bestScore >= distPresent { return .present(r, n, bestScore) }
        if bestScore >= distReview { return .review(r, n, bestScore) }
        return .none
    }

    // MARK: math
    
    private func normalize(_ v: [Float]) -> [Float] {
        let mag = sqrt(v.map { $0 * $0 }.reduce(0, +))
        if mag == 0 { return v }
        return v.map { $0 / mag }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return -1.0 }
        var dotProduct: Float = 0.0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
        }
        // Since vectors are pre-normalized, dot product == cosine similarity
        return dotProduct
    }

    // MARK: persistence
    
    private struct SavedData: Codable {
        let register: String
        let name: String
        let prints: [[Float]]
    }

    private func save() {
        let data = enrolled.values.map { SavedData(register: $0.register, name: $0.name, prints: $0.prints) }
        if let j = try? JSONEncoder().encode(data) {
            try? j.write(to: store)
        }
    }

    private func load() {
        if let d = try? Data(contentsOf: store),
           let arr = try? JSONDecoder().decode([SavedData].self, from: d) {
            for s in arr {
                enrolled[s.register] = Enrolled(register: s.register, name: s.name, prints: s.prints)
            }
        }
    }
}
