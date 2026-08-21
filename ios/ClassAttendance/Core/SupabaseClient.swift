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

    /// Who is signed in — a teacher (has an app_user row) or a student (has a student
    /// row), decided by which table their auth.uid() can read under RLS.
    enum Role: Equatable {
        case teacher(name: String)
        case student(name: String, register: String, studentId: String)
    }

    static func currentRole() async -> Role? {
        struct T: Decodable { let full_name: String }
        if let d = try? await send(request(
            URL(string: "\(restURL)/app_user?select=full_name&limit=1")!, authenticated: true)),
           let t = (try? JSONDecoder().decode([T].self, from: d))?.first {
            return .teacher(name: t.full_name)
        }
        struct S: Decodable { let id: String; let full_name: String; let register_no: String }
        if let d = try? await send(request(
            URL(string: "\(restURL)/student?select=id,full_name,register_no&limit=1")!, authenticated: true)),
           let s = (try? JSONDecoder().decode([S].self, from: d))?.first {
            return .student(name: s.full_name, register: s.register_no, studentId: s.id)
        }
        return nil
    }

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
        r.timeoutInterval = 20   // fail fast instead of hanging the sign-in spinner
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
        r.timeoutInterval = 20   // fail fast instead of hanging
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
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let e as URLError {
            // Translate low-level network failures into something a person can act on.
            switch e.code {
            case .timedOut:
                throw AuthError(errorDescription: "Couldn't reach the server (timed out). Check your internet — or, if you're running on the Mac, that the app is allowed network access.")
            case .notConnectedToInternet, .networkConnectionLost:
                throw AuthError(errorDescription: "No internet connection.")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw AuthError(errorDescription: "Can't connect to the server. Check your network.")
            default:
                throw AuthError(errorDescription: "Network error: \(e.localizedDescription)")
            }
        }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if allowAuthErrors { return data }   // caller decodes the error body itself
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Supabase", code: code, userInfo: [
                NSLocalizedDescriptionKey: "Request failed (\(code)): "
                    + (String(data: data, encoding: .utf8) ?? "no body")])
        }
        return data
    }

    /// The signed-in teacher's own app_user id (self-read via RLS).
    private static func myTeacherId() async throws -> String {
        let data = try await send(request(
            URL(string: "\(restURL)/app_user?select=id&limit=1")!, authenticated: true))
        struct U: Decodable { let id: String }
        guard let id = (try JSONDecoder().decode([U].self, from: data)).first?.id else {
            throw AuthError(errorDescription: "No teacher profile is linked to this account.")
        }
        return id
    }

    private static func roomId(forSection sectionId: String) async throws -> String? {
        var comp = URLComponents(string: "\(restURL)/section")!
        comp.queryItems = [.init(name: "id", value: "eq.\(sectionId)"),
                           .init(name: "select", value: "room_id")]
        let data = try await send(request(comp.url!, authenticated: true))
        struct S: Decodable { let room_id: String? }
        return (try? JSONDecoder().decode([S].self, from: data))?.first?.room_id ?? nil
    }

    /// Write a submitted attendance session + one record per rostered student, for
    /// the ACTUAL class being taken. Requires a signed-in teacher (RLS-scoped).
    static func submitAttendance(sectionId: String, presentRegisters: Set<String>) async throws {
        guard accessToken != nil else {
            throw AuthError(errorDescription: "Sign in as a teacher first (Settings → Cloud sync).")
        }
        let teacherId = try await myTeacherId()
        let roomId = try await roomId(forSection: sectionId)

        // roster for THIS class: register_no -> student id
        var comp = URLComponents(string: "\(restURL)/section_roster")!
        comp.queryItems = [.init(name: "section_id", value: "eq.\(sectionId)"),
                           .init(name: "select", value: "student(id,register_no)")]
        let rData = try await send(request(comp.url!, authenticated: true))
        struct RRow: Decodable { let student: S; struct S: Decodable { let id: String; let register_no: String } }
        let roster = try JSONDecoder().decode([RRow].self, from: rData)

        var sBody: [String: Any] = ["section_id": sectionId, "teacher_id": teacherId,
                                    "capture_path": "iphone", "status": "submitted"]
        if let roomId { sBody["room_id"] = roomId }
        let sData = try await send(
            request(URL(string: "\(restURL)/attendance_session")!,
                    method: "POST", json: [sBody], prefer: "return=representation", authenticated: true))
        struct Sess: Decodable { let id: String }
        guard let sid = (try JSONDecoder().decode([Sess].self, from: sData)).first?.id else {
            throw URLError(.badServerResponse)
        }

        let records: [[String: Any]] = roster.map {
            ["session_id": sid, "student_id": $0.student.id,
             "status": presentRegisters.contains($0.student.register_no) ? "present" : "absent",
             "source": "auto"]
        }
        _ = try await send(
            request(URL(string: "\(restURL)/attendance_record")!,
                    method: "POST", json: records, prefer: "return=minimal", authenticated: true))
    }

    // MARK: - Phase 1: teacher's class dataset (enroll to cloud / download to phone)

    struct RosterStudent: Identifiable, Decodable, Hashable {
        let id: String
        let register_no: String
        let full_name: String
    }

    /// Students in one of the teacher's own classes (RLS scopes to owned rosters).
    static func rosterStudents(sectionId: String) async throws -> [RosterStudent] {
        var comp = URLComponents(string: "\(restURL)/section_roster")!
        comp.queryItems = [.init(name: "section_id", value: "eq.\(sectionId)"),
                           .init(name: "select", value: "student(id,register_no,full_name)")]
        let data = try await send(request(comp.url!, authenticated: true))
        struct Row: Decodable { let student: RosterStudent }
        return try JSONDecoder().decode([Row].self, from: data).map(\.student)
    }

    /// One enrolled student, ready for the on-device recogniser.
    struct EnrolledPerson { let register: String; let name: String; let prints: [[Float]] }

    /// Download a class's whole face dataset (roster + active templates), grouped per
    /// student → feeds the on-device matcher. This IS the "teacher's dataset lives on
    /// the phone" pull. One roster fetch + one templates fetch.
    static func downloadClassDataset(sectionId: String) async throws -> [EnrolledPerson] {
        let students = try await rosterStudents(sectionId: sectionId)
        guard !students.isEmpty else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        let ids = students.map(\.id).joined(separator: ",")

        var comp = URLComponents(string: "\(restURL)/face_template")!
        comp.queryItems = [.init(name: "student_id", value: "in.(\(ids))"),
                           .init(name: "is_active", value: "eq.true"),
                           .init(name: "select", value: "student_id,embedding")]
        let data = try await send(request(comp.url!, authenticated: true))
        struct Raw: Decodable { let student_id: String; let embedding: EmbeddingValue }
        let raws = try JSONDecoder().decode([Raw].self, from: data)

        var printsById: [String: [[Float]]] = [:]
        for r in raws { printsById[r.student_id, default: []].append(r.embedding.floats) }
        return printsById.compactMap { sid, prints in
            guard let s = byId[sid] else { return nil }
            return EnrolledPerson(register: s.register_no, name: s.full_name, prints: prints)
        }
    }

    /// pgvector arrives either as a JSON array or as a "[...]" string — handle both.
    struct EmbeddingValue: Decodable {
        let floats: [Float]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let arr = try? c.decode([Float].self) { floats = arr; return }
            let s = try c.decode(String.self)
            floats = s.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        }
    }

    /// Upload the captured face templates for a rostered student (consent + templates).
    /// Deactivates previous templates so re-enrolment replaces cleanly. Teacher only.
    static func uploadTemplates(studentId: String, templates: [[Float]],
                                modelVersion: String = "sface-2021dec") async throws {
        guard accessToken != nil else {
            throw AuthError(errorDescription: "Sign in as a teacher first (Settings → Sign in).")
        }
        // 1) consent row (biometric write requires it)
        let cData = try await send(request(URL(string: "\(restURL)/consent")!, method: "POST",
            json: [["student_id": studentId, "policy_version": "v1", "granted_by": demoTeacher]],
            prefer: "return=representation", authenticated: true))
        struct C: Decodable { let id: String }
        guard let consentId = (try JSONDecoder().decode([C].self, from: cData)).first?.id else {
            throw URLError(.badServerResponse)
        }
        // 2) retire any existing templates for this student
        _ = try? await send(request(
            URL(string: "\(restURL)/face_template?student_id=eq.\(studentId)")!,
            method: "PATCH", json: ["is_active": false], prefer: "return=minimal", authenticated: true))
        // 3) insert the new templates (pgvector wants a "[...]" string)
        let rows: [[String: Any]] = templates.map { emb in
            ["student_id": studentId,
             "embedding": "[" + emb.map { String($0) }.joined(separator: ",") + "]",
             "model_version": modelVersion, "quality_score": 1.0,
             "consent_id": consentId, "is_active": true]
        }
        _ = try await send(request(URL(string: "\(restURL)/face_template")!, method: "POST",
            json: rows, prefer: "return=minimal", authenticated: true))
    }

    // MARK: - Student self-view

    struct StudentClass: Decodable, Identifiable {
        let id: String
        let course: Course
        let schedule: [Sched]
        struct Course: Decodable { let code: String; let title: String }
        struct Sched: Decodable { let day_of_week: Int?; let start_time: String }
    }

    /// The signed-in student's enrolled classes (RLS-scoped to them).
    static func studentClasses() async throws -> [StudentClass] {
        var comp = URLComponents(string: "\(restURL)/section")!
        comp.queryItems = [.init(name: "select", value: "id,course(code,title),schedule(day_of_week,start_time)")]
        let data = try await send(request(comp.url!, authenticated: true))
        return try JSONDecoder().decode([StudentClass].self, from: data)
    }

    /// The signed-in student's attendance so far: (present, total).
    static func studentAttendance() async throws -> (present: Int, total: Int) {
        let data = try await send(request(
            URL(string: "\(restURL)/attendance_record?select=status")!, authenticated: true))
        struct R: Decodable { let status: String }
        let rows = try JSONDecoder().decode([R].self, from: data)
        return (rows.filter { $0.status == "present" }.count, rows.count)
    }

    private static let sectionSelect =
        "id,course(code,title),room(code,building(name))," +
        "schedule(day_of_week,start_time,end_time),section_roster(count)"

    static func fetchSections() async throws -> [ClassSection] {
        var comp = URLComponents(string: "\(restURL)/section")!
        comp.queryItems = [URLQueryItem(name: "select", value: sectionSelect)]
        let data = try await send(request(comp.url!))
        return try JSONDecoder().decode([SectionRow].self, from: data).map { $0.toSection() }
    }

    /// The signed-in teacher's OWN classes only (RLS-scoped). Empty if not signed in.
    static func myClasses() async throws -> [ClassSection] {
        guard accessToken != nil else { return [] }
        var comp = URLComponents(string: "\(restURL)/section")!
        comp.queryItems = [URLQueryItem(name: "select", value: sectionSelect)]
        let data = try await send(request(comp.url!, authenticated: true))
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
