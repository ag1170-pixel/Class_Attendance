import Foundation

/// Reads live class data from Supabase via its REST API (PostgREST) using the
/// publishable key. Read-only, and only the class/schedule tables are exposed
/// (biometrics + attendance stay locked by row-level security).
enum Supabase {
    static let restURL = "https://mystjdepvvmfihcpiftx.supabase.co/rest/v1"
    static let key = "sb_publishable_HvyNIVQ4emjhfQb5ZlkVmg_rCW9cvix"

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
