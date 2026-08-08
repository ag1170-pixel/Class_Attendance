import Foundation

/// Local demo data so the app runs on a device with no backend yet.
/// Swap these for live Supabase calls in the next milestone (see docs/05_ROADMAP.md).
enum DemoData {
    static let today = "Fri"

    static let sections: [ClassSection] = [
        ClassSection(id: "CS301", courseCode: "CS301", courseTitle: "Operating Systems",
                     roomCode: "A-101", startTime: "09:00", endTime: "10:00",
                     building: "Main Block", day: "Fri", isNow: true, studentCount: 42),
        ClassSection(id: "CS410", courseCode: "CS410", courseTitle: "Networks",
                     roomCode: "B-204", startTime: "11:00", endTime: "12:00",
                     building: "Science Block", day: "Fri", isNow: false, studentCount: 38),
        ClassSection(id: "CS250", courseCode: "CS250", courseTitle: "Data Structures",
                     roomCode: "A-101", startTime: "14:00", endTime: "15:00",
                     building: "Main Block", day: "Wed", isNow: false, studentCount: 51),
    ]

    /// Courses a teacher can add by scanning a course QR.
    static let addable: [ClassSection] = [
        ClassSection(id: "CS520", courseCode: "CS520", courseTitle: "Machine Learning",
                     roomCode: "C-310", startTime: "15:30", endTime: "16:30",
                     building: "Tech Park", day: "Thu", isNow: false, studentCount: 45),
        ClassSection(id: "MA201", courseCode: "MA201", courseTitle: "Discrete Mathematics",
                     roomCode: "B-105", startTime: "10:00", endTime: "11:00",
                     building: "Science Block", day: "Mon", isNow: false, studentCount: 60),
    ]

    struct PastSession: Identifiable, Hashable {
        let id = UUID()
        let title: String, when: String, present: Int, total: Int
    }

    static let history: [PastSession] = [
        .init(title: "CS301 · Operating Systems", when: "Today · 9:00", present: 39, total: 42),
        .init(title: "CS410 · Networks", when: "Wed · 11:00", present: 36, total: 38),
        .init(title: "CS250 · Data Structures", when: "Tue · 14:00", present: 48, total: 51),
        .init(title: "CS301 · Operating Systems", when: "Mon · 9:00", present: 40, total: 42),
    ]

    /// A pre-filled roster the "camera" would return — SRM register format.
    static func review() -> [ReviewRow] {
        func row(_ reg: String, _ name: String, _ present: Bool, _ conf: Double?) -> ReviewRow {
            ReviewRow(studentId: reg, registerNo: reg, fullName: name,
                      status: present ? .present : .absent,
                      source: .auto, confidence: present ? conf : nil)
        }
        return [
            row("RA2411026010074", "Aarav Sharma", true, 0.94),
            row("RA2411026010075", "Diya Patel", true, 0.91),
            row("RA2411026010076", "Kabir Singh", false, nil),
            row("RA2411026010077", "Ananya Rao", true, 0.88),
            row("RA2411026010078", "Vivaan Gupta", true, 0.79),
            row("RA2411026010079", "Isha Nair", false, nil),
            row("RA2411026010080", "Rohan Mehta", true, 0.86),
        ]
    }
}
