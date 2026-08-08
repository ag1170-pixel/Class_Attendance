import SwiftUI

/// Today's classes for the signed-in teacher. Tapping one opens the attendance
/// flow. Sections come from the backend (GET /sections).
struct ScheduleView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var sections: [ClassSection] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if let loadError {
                    Text(loadError).foregroundStyle(.red)
                }
                Section("Today") {
                    ForEach(sections) { s in
                        NavigationLink(value: s) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(s.courseCode) · \(s.courseTitle)").font(.headline)
                                Text("Room \(s.roomCode) · \(s.startTime)–\(s.endTime)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hi, \(auth.teacherName)")
            .navigationDestination(for: ClassSection.self) { AttendanceView(section: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { EnrollmentView() } label: {
                        Label("Enroll", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { auth.signOut() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            sections = try await APIClient.shared.mySections()
        } catch {
            loadError = "Could not load classes: \(error.localizedDescription)"
        }
    }
}
