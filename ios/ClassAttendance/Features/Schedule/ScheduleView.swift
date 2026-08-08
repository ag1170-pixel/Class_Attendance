import SwiftUI

/// Today's classes for the signed-in teacher. Search, or add a course by QR.
struct ScheduleView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var classes = DemoData.sections
    @State private var query = ""
    @State private var showScanner = false

    private var filtered: [ClassSection] {
        query.isEmpty ? classes : classes.filter {
            "\($0.courseCode) \($0.courseTitle)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    ForEach(filtered) { c in
                        NavigationLink(value: c) { ClassRow(section: c) }
                    }
                    if filtered.isEmpty {
                        Text("No classes match. Add one with ").foregroundStyle(Theme.dim)
                            + Text(Image(systemName: "qrcode.viewfinder")) + Text(".")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search your classes")
            .navigationTitle("Hi, \(auth.teacherName)")
            .navigationDestination(for: ClassSection.self) { AttendanceView(section: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                AddCourseSheet { added in
                    if !classes.contains(where: { $0.id == added.id }) { classes.append(added) }
                    showScanner = false
                }
            }
        }
    }
}

/// Scan a course QR to add it (demo: simulated detection).
struct AddCourseSheet: View {
    let onAdd: (ClassSection) -> Void
    @State private var found: ClassSection?

    var body: some View {
        VStack(spacing: 20) {
            Capsule().frame(width: 40, height: 5).foregroundStyle(Theme.dim.opacity(0.4)).padding(.top, 10)
            Text("Scan course QR").font(.title2.bold())
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Theme.surface2).frame(height: 220)
                Image(systemName: "qrcode.viewfinder").font(.system(size: 72)).foregroundStyle(Theme.accent)
            }.padding(.horizontal)
            Text(found == nil ? "Point at the course QR…"
                 : "Found: \(found!.courseCode) · \(found!.courseTitle)")
                .foregroundStyle(found == nil ? Theme.dim : Theme.present)
            Spacer()
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            let c = DemoData.addable.first!
            found = c
            try? await Task.sleep(nanoseconds: 800_000_000)
            onAdd(c)
        }
    }
}
