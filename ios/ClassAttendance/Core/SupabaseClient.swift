import Foundation

/// Reads live class data from Supabase via its REST API (PostgREST) using the
/// publishable key. Read-only, and only the class/schedule tables are exposed
/// (biometrics + attendance stay locked by row-level security).
enum Supabase {
    static let restURL = "https://mystjdepvvmfihcpiftx.supabase.co/rest/v1"
    static let key = "sb_publishable_HvyNIVQ4emjhfQb5ZlkVmg_rCW9cvix"

    // Seeded demo class in the cloud (shared with the Mac).
    static let demoSection = "77777777-7777-7777-7777-777777777777"
    static let demoTeacher = "55555555-5555-5555-5555-555555555555"
    static let demoRoom = "33333333-3333-3333-3333-333333333333"

    private static func request(_ url: URL, method: String = "GET",
                                json: Any? = nil, prefer: String? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let json { r.httpBody = try? JSONSerialization.data(withJSONObject: json) }
        return r
    }

    /// Write a submitted attendance session + one record per rostered student.
    static func submitAttendance(presentRegisters: Set<String>) async throws {
        // 1) roster: register_no -> student id
        var comp = URLComponents(string: "\(restURL)/section_roster")!
        comp.queryItems = [.init(name: "section_id", value: "eq.\(demoSection)"),
                           .init(name: "select", value: "student(id,register_no)")]
        let (rData, _) = try await URLSession.shared.data(for: request(comp.url!))
        struct RRow: Decodable { let student: S; struct S: Decodable { let id: String; let register_no: String } }
        let roster = try JSONDecoder().decode([RRow].self, from: rData)

        // 2) create the session
        let sBody: [String: Any] = ["section_id": demoSection, "teacher_id": demoTeacher,
                                    "room_id": demoRoom, "capture_path": "iphone", "status": "submitted"]
        let (sData, _) = try await URLSession.shared.data(
            for: request(URL(string: "\(restURL)/attendance_session")!,
                         method: "POST", json: [sBody], prefer: "return=representation"))
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
        _ = try await URLSession.shared.data(
            for: request(URL(string: "\(restURL)/attendance_record")!,
                         method: "POST", json: records, prefer: "return=minimal"))
    }

    static func fetchSections() async throws -> [ClassSection] {
        let select = "id,course(code,title),room(code,building(name))," +
                     "schedule(day_of_week,start_time,end_time),section_roster(count)"
        var comp = URLComponents(string: "\(restURL)/section")!
        comp.queryItems = [URLQueryItem(name: "select", value: select)]
        var req = URLRequest(url: comp.url!)
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
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
