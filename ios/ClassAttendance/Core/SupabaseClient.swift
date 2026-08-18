import Foundation
import Security

/// Reads live class data from Supabase via its REST API (PostgREST) using the
/// public anon key. Writes (attendance) require a signed-in teacher — Supabase Auth
/// scopes them via row-level security to that teacher's own sections (see
/// docs/SECURITY_REVIEW.md for why: the anon key ships inside the app binary, so
/// anyone can extract it — it must never be able to write or read student PII).
enum Supabase {
    static let restURL = "https://mystjdepvvmfihcpiftx.supabase.co/rest/v1"
    static let authURL = "https://mystjdepvvmfihcpiftx.supabase.co/auth/v1"
    static let key = "sb_publishable_HvyNIVQ4emjhfQb5ZlkVmg_rCW9cvix"

    // Seeded demo class in the cloud (shared with the Mac).
    static let demoSection = "77777777-7777-7777-7777-777777777777"
    static let demoTeacher = "55555555-5555-5555-5555-555555555555"
    static let demoRoom = "33333333-3333-3333-3333-333333333333"

    // MARK: - Teacher session (Keychain-backed)

    private static var accessToken: String?
    private static var refreshToken: String? {
        get { Keychain.read("supabase_refresh_token") }
        set {
            if let v = newValue { Keychain.write("supabase_refresh_token", value: v) }
            else { Keychain.delete("supabase_refresh_token") }
        }
    }

    static var isSignedIn: Bool { refreshToken != nil }

    struct AuthError: LocalizedError {
        let errorDescription: String?
    }

    static func signIn(email: String, password: String) async throws {
        let data = try await send(authRequest("/token?grant_type=password",
            json: ["email": email, "password": password]), allowAuthErrors: true)
        try storeSession(from: data)
    }

    static func signOut() {
        accessToken = nil
        refreshToken = nil
    }

    /// Called at app launch: silently restore the session from the stored refresh
    /// token, if any. Never prompts — the login screen handles that when it fails.
    static func restoreSession() async {
        guard let rt = refreshToken else { return }
        guard let data = try? await send(authRequest("/token?grant_type=refresh_token",
            json: ["refresh_token": rt])) else { return }
        try? storeSession(from: data)
    }

    private static func storeSession(from data: Data) throws {
        struct Session: Decodable { let access_token: String; let refresh_token: String }
        guard let s = try? JSONDecoder().decode(Session.self, from: data) else {
            struct ErrBody: Decodable { let msg: String? ; let error_description: String? }
            let msg = (try? JSONDecoder().decode(ErrBody.self, from: data))?.msg
                ?? (try? JSONDecoder().decode(ErrBody.self, from: data))?.error_description
                ?? "Sign-in failed"
            throw AuthError(errorDescription: msg)
        }
        accessToken = s.access_token
        refreshToken = s.refresh_token
    }

    private static func authRequest(_ path: String, json: [String: Any]) -> URLRequest {
        var r = URLRequest(url: URL(string: authURL + path)!)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: json)
        return r
    }

    // MARK: - REST requests

    private static func request(_ url: URL, method: String = "GET",
                                json: Any? = nil, prefer: String? = nil,
                                authenticated: Bool = false) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "apikey")   // always required by the gateway
        // Writes use the signed-in teacher's token (RLS scopes them to their own
        // sections); reads use the anon key (only non-sensitive class/schedule data
        // is anon-readable — see docs/SECURITY_REVIEW.md).
        let bearer = (authenticated ? accessToken : nil) ?? key
        r.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let json { r.httpBody = try? JSONSerialization.data(withJSONObject: json) }
        return r
    }

    /// Fires the request and throws unless the response is 2xx — never let a
    /// blocked write (RLS, auth, etc.) look like a silent success.
    private static func send(_ req: URLRequest, allowAuthErrors: Bool = false) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if allowAuthErrors { return data }   // caller decodes the error body itself
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Supabase", code: code, userInfo: [
                NSLocalizedDescriptionKey: "Request failed (\(code)): "
                    + (String(data: data, encoding: .utf8) ?? "no body")])
        }
        return data
    }

    /// Write a submitted attendance session + one record per rostered student.
    /// Requires a signed-in teacher — see docs/SECURITY_REVIEW.md.
    static func submitAttendance(presentRegisters: Set<String>) async throws {
        guard accessToken != nil else {
            throw AuthError(errorDescription: "Sign in as a teacher first (Settings → Sign in).")
        }
        // 1) roster: register_no -> student id (own roster only, per RLS)
        var comp = URLComponents(string: "\(restURL)/section_roster")!
        comp.queryItems = [.init(name: "section_id", value: "eq.\(demoSection)"),
                           .init(name: "select", value: "student(id,register_no)")]
        let rData = try await send(request(comp.url!, authenticated: true))
        struct RRow: Decodable { let student: S; struct S: Decodable { let id: String; let register_no: String } }
        let roster = try JSONDecoder().decode([RRow].self, from: rData)

        // 2) create the session
        let sBody: [String: Any] = ["section_id": demoSection, "teacher_id": demoTeacher,
                                    "room_id": demoRoom, "capture_path": "iphone", "status": "submitted"]
        let sData = try await send(
            request(URL(string: "\(restURL)/attendance_session")!,
                    method: "POST", json: [sBody], prefer: "return=representation", authenticated: true))
        struct Sess: Decodable { let id: String }
        guard let sid = (try JSONDecoder().decode([Sess].self, from: sData)).first?.id else {
            throw URLError(.badServerResponse)
        }

        // 3) one record per student
        let records: [[String: Any]] = roster.map {
            ["session_id": sid, "student_id": $0.student.id,
             "status": presentRegisters.contains($0.student.register_no) ? "present" : "absent",
             "source": "auto"]
        }
        _ = try await send(
            request(URL(string: "\(restURL)/attendance_record")!,
                    method: "POST", json: records, prefer: "return=minimal", authenticated: true))
    }

    static func fetchSections() async throws -> [ClassSection] {
        let select = "id,course(code,title),room(code,building(name))," +
                     "schedule(day_of_week,start_time,end_time),section_roster(count)"
        var comp = URLComponents(string: "\(restURL)/section")!
        comp.queryItems = [URLQueryItem(name: "select", value: select)]
        let data = try await send(request(comp.url!))
        return try JSONDecoder().decode([SectionRow].self, from: data).map { $0.toSection() }
    }

    private struct SectionRow: Decodable {
        let id: String
        let course: Course?
        let room: Room?
        let schedule: [Sched]
        let section_roster: [CountRow]

        struct Course: Decodable { let code: String; let title: String }
        struct Room: Decodable { let code: String; let building: Building? }
        struct Building: Decodable { let name: String }
        struct Sched: Decodable { let day_of_week: Int?; let start_time: String; let end_time: String }
        struct CountRow: Decodable { let count: Int }

        func toSection() -> ClassSection {
            let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let s = schedule.first
            let day = s?.day_of_week.flatMap { (0..<7).contains($0) ? days[$0] : nil }
            return ClassSection(
                id: id,
                courseCode: course?.code ?? "?",
                courseTitle: course?.title ?? "Class",
                roomCode: room?.code ?? "-",
                startTime: String((s?.start_time ?? "").prefix(5)),
                endTime: String((s?.end_time ?? "").prefix(5)),
                building: room?.building?.name,
                day: day,
                isNow: day == DemoData.today,
                studentCount: section_roster.first?.count ?? 0)
        }
    }
}

/// Minimal Keychain wrapper — just enough to persist the refresh token securely
/// across launches (never store it in UserDefaults/plist).
private enum Keychain {
    static func write(_ key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
