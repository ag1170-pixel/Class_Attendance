import SwiftUI

@main
struct ClassAttendanceApp: App {
    @StateObject private var session = SessionManager()
    @StateObject private var timetable = TimetableStore()
    @State private var restored = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !restored {
                    // brief splash while we restore any stored session
                    ProgressView().controlSize(.large)
                        .task {
                            await session.restore()
                            restored = true
                        }
                } else if session.isSignedIn {
                    if session.isTeacher {
                        MainTabView()
                    } else {
                        StudentHomeView()
                    }
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .environmentObject(timetable)
        }
    }
}
