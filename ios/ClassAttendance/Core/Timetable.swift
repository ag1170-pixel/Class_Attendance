import Foundation
import Combine

/// One class in the user's personal weekly timetable (entered once, stored on the
/// phone). day: 0=Mon … 6=Sun. Times are "HH:mm".
struct TimetableEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var courseCode: String
    var courseTitle: String
    var room: String
    var building: String
    var day: Int
    var startTime: String   // "HH:mm"
    var endTime: String     // "HH:mm"

    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var dayName: String { (0..<7).contains(day) ? Self.dayNames[day] : "?" }

    var startMinutes: Int { Self.minutes(startTime) }
    var endMinutes: Int { Self.minutes(endTime) }

    static func minutes(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return 0 }
        return h * 60 + m
    }
}

/// The user's timetable — persisted locally (UserDefaults JSON). No backend.
@MainActor
final class TimetableStore: ObservableObject {
    @Published var entries: [TimetableEntry] = [] { didSet { save() } }

    private let key = "personal_timetable_v1"

    init() { load() }

    func add(_ e: TimetableEntry) { entries.append(e); sort() }
    func remove(at offsets: IndexSet) { entries.remove(atOffsets: offsets) }
    func remove(_ e: TimetableEntry) { entries.removeAll { $0.id == e.id } }

    func entries(on day: Int) -> [TimetableEntry] {
        entries.filter { $0.day == day }.sorted { $0.startMinutes < $1.startMinutes }
    }

    private func sort() {
        entries.sort { ($0.day, $0.startMinutes) < ($1.day, $1.startMinutes) }
    }

    // MARK: next class

    /// Minutes from `now` until this entry's next occurrence (this week or next).
    private func minutesUntil(_ e: TimetableEntry, from now: Date) -> Int {
        let cal = Calendar.current
        let todayIdx = (cal.component(.weekday, from: now) + 5) % 7   // Sun=1 → 6, Mon=2 → 0
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        var dayDelta = (e.day - todayIdx + 7) % 7
        if dayDelta == 0 && e.startMinutes <= nowMin { dayDelta = 7 }  // already started/passed today
        return dayDelta * 24 * 60 + (e.startMinutes - nowMin)
    }

    /// The soonest upcoming class, and how many minutes until it starts.
    func nextClass(from now: Date = Date()) -> (entry: TimetableEntry, minutesUntil: Int)? {
        entries
            .map { ($0, minutesUntil($0, from: now)) }
            .min { $0.1 < $1.1 }
            .map { (entry: $0.0, minutesUntil: $0.1) }
    }

    // MARK: persistence

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TimetableEntry].self, from: data) else { return }
        entries = decoded
    }
}

/// Human-friendly "in 25 min" / "in 2 h 10 m" / "in 3 days".
func countdownText(minutes: Int) -> String {
    if minutes <= 0 { return "now" }
    if minutes < 60 { return "in \(minutes) min" }
    if minutes < 24 * 60 {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "in \(h) h" : "in \(h) h \(m) m"
    }
    let days = minutes / (24 * 60)
    return days == 1 ? "tomorrow" : "in \(days) days"
}
