import Foundation

// DTOs mirroring the backend API (backend/api.py) and schema.

struct ClassSection: Identifiable, Codable, Hashable {
    let id: String
    let courseCode: String
    let courseTitle: String
    let roomCode: String
    let startTime: String      // "HH:MM"
    let endTime: String
    var building: String? = nil
    var day: String? = nil       // "Mon"…"Fri"
    var isNow: Bool = false
    var studentCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case courseCode = "course_code"
        case courseTitle = "course_title"
        case roomCode = "room_code"
        case startTime = "start_time"
        case endTime = "end_time"
        case building
        case day
        case isNow = "is_now"
        case studentCount = "student_count"
    }
}

struct CreateSessionResponse: Codable {
    let sessionId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status
    }
}

enum AttendanceStatus: String, Codable {
    case present
    case absent
}

enum AttendanceSource: String, Codable {
    case auto
    case manualOverride = "manual_override"
}

struct ReviewRow: Identifiable, Codable, Hashable {
    var id: String { studentId }
    let studentId: String
    let registerNo: String
    let fullName: String
    var status: AttendanceStatus
    var source: AttendanceSource
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case studentId = "student_id"
        case registerNo = "register_no"
        case fullName = "full_name"
        case status, source, confidence
    }
}

struct ReviewResponse: Codable {
    let rows: [ReviewRow]
    let summary: Summary

    struct Summary: Codable {
        let present: Int
        let absent: Int
        let total: Int
    }
}
