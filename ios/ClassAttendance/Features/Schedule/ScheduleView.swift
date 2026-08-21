import SwiftUI

/// Today's classes for the signed-in teacher. Search, or add a course by QR.
struct ScheduleView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var timetable: TimetableStore
    @State private var classes = DemoData.sections
    @State private var query = ""
    @State private var showScanner = false
    @State private var live = false

    private var filtered: [ClassSection] {
        query.isEmpty ? classes : classes.filter {
            "\($0.courseCode) \($0.courseTitle)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if timetable.nextClass() != nil {
                    Section {
                        NextClassCard(store: timetable)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
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
            .refreshable { await loadLive() }
            .task { await loadLive() }
            .navigationTitle("Hi, \(session.firstName)")
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
            .overlay(alignment: .bottom) {
                Text(Supabase.isSignedIn ? "● Your classes (live)"
                     : (live ? "● Public class list" : "○ Demo data (offline)"))
                    .font(.caption2).foregroundStyle(live || Supabase.isSignedIn ? Theme.present : Theme.dim)
                    .padding(.bottom, 4)
            }
        }
    }

    private func loadLive() async {
        // Signed-in teacher → show ONLY their own classes (each taps through to
        // attendance, which auto-syncs that class's face dataset to the phone).
        await Supabase.restoreSession()
        if Supabase.isSignedIn, let mine = try? await Supabase.myClasses(), !mine.isEmpty {
            classes = mine
            live = true
            return
        }
        // Signed out → the public class list (demo / offline).
        if let fetched = try? await Supabase.fetchSections(), !fetched.isEmpty {
            classes = fetched
            live = true
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
