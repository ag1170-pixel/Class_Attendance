import Foundation

/// Thin async client over the backend API (backend/api.py).
/// Uses async/await URLSession. In production add TLS certificate pinning and
/// replace the X-User-Id header with an SSO/JWT bearer token.
actor APIClient {
    static let shared = APIClient()

    // Point at your running backend. For the simulator, localhost works.
    var baseURL = URL(string: "http://127.0.0.1:8000")!
    var userId: String = ""      // set at login (stands in for JWT subject)

    private let session = URLSession(configuration: .default)

    func configure(baseURL: URL, userId: String) {
        self.baseURL = baseURL
        self.userId = userId
    }

    // MARK: - Requests

    func mySections() async throws -> [ClassSection] {
        try await get("/sections", as: [ClassSection].self)
    }

    func createSession(sectionId: String, capturePath: String = "webcam") async throws -> CreateSessionResponse {
        try await post("/sessions",
                       body: ["section_id": sectionId, "capture_path": capturePath],
                       as: CreateSessionResponse.self)
    }

    func review(sessionId: String) async throws -> ReviewResponse {
        try await get("/sessions/\(sessionId)/review", as: ReviewResponse.self)
    }

    func override(sessionId: String, studentId: String, status: AttendanceStatus) async throws {
        _ = try await postRaw("/sessions/\(sessionId)/override",
                              body: ["student_id": studentId, "status": status.rawValue])
    }

    func submit(sessionId: String) async throws {
        _ = try await postRaw("/sessions/\(sessionId)/submit", body: [:])
    }

    // MARK: - Plumbing

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userId, forHTTPHeaderField: "X-User-Id")
        return req
    }

    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let (data, resp) = try await session.data(for: makeRequest(path, method: "GET"))
        try Self.check(resp, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], as: T.Type) async throws -> T {
        let data = try await postRaw(path, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func postRaw(_ path: String, body: [String: Any]) async throws -> Data {
        var req = makeRequest(path, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        return data
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "APIClient", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
