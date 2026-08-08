import SwiftUI

@main
struct ClassAttendanceApp: App {
    // Wire the demo teacher + backend here. Replace with SSO in production.
    // teacherId must match a seeded app_user id (see `python -m backend.seed`).
    @StateObject private var auth = AuthManager(
        teacherId: ProcessInfo.processInfo.environment["TEACHER_ID"] ?? "SEED_TEACHER_ID",
        teacherName: "Prof. Rao",
        backendURL: URL(string: ProcessInfo.processInfo.environment["BACKEND_URL"]
                        ?? "http://127.0.0.1:8000")!
    )

    var body: some Scene {
        WindowGroup {
            if auth.isAuthenticated {
                if ProcessInfo.processInfo.arguments.contains("-demoreview") {
                    NavigationStack { AttendanceView(section: DemoData.sections[0]) }
                        .environmentObject(auth)
                } else {
                    MainTabView().environmentObject(auth)
                }
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
    }
}
