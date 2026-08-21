import SwiftUI

/// The student app — bold, friendly, at-a-glance. Their attendance %, a one-tap
/// Face-ID check-in, and their classes. (Teachers get the professional app instead.)
struct StudentHomeView: View {
    @EnvironmentObject var session: SessionManager
    @State private var present = 0
    @State private var total = 0
    @State private var classes: [Supabase.StudentClass] = []
    @State private var showCheckIn = false
    @State private var loading = true

    private var pct: Int { total == 0 ? 0 : present * 100 / total }
    private var short: Bool { total > 0 && pct < 75 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    checkInButton
                    classesCard
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Hey, \(session.firstName) 👋")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let r = session.studentRegister { Text(r) }
                        Button("Sign out", role: .destructive) { session.signOut() }
                    } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showCheckIn) {
                NavigationStack { CheckInView(register: session.studentRegister ?? "") }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text("YOUR ATTENDANCE").font(.caption.weight(.bold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.85))
            Text(total == 0 ? "—" : "\(pct)%")
                .font(.system(size: 62, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).contentTransition(.numericText())
            Text(total == 0 ? "No classes marked yet" : "\(present) of \(total) classes present")
                .font(.subheadline).foregroundStyle(.white.opacity(0.92))
            if short {
                Text("⚠︎ Below 75% — don't miss the next one")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.22), in: Capsule()).foregroundStyle(.white)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(
            LinearGradient(colors: short ? [Theme.absent, Color(red: 1, green: 0.42, blue: 0.36)]
                                         : [Theme.accent, Color(red: 0.46, green: 0.28, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: (short ? Theme.absent : Theme.accent).opacity(0.32), radius: 18, y: 10)
    }

    private var checkInButton: some View {
        Button { showCheckIn = true } label: {
            Label("Check in to class", systemImage: "faceid")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(FilledButton())
    }

    private var classesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("My classes").font(.headline)
            if classes.isEmpty {
                Text(loading ? "Loading…" : "You're not enrolled in any classes yet.")
                    .foregroundStyle(Theme.dim).font(.subheadline)
            } else {
                ForEach(classes) { c in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.15))
                            .frame(width: 44, height: 44)
                            .overlay(Text(c.course.code.prefix(2))
                                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.course.title).font(.subheadline.weight(.semibold))
                            Text(c.course.code + dayTime(c)).font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func dayTime(_ c: Supabase.StudentClass) -> String {
        guard let s = c.schedule.first else { return "" }
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let d = s.day_of_week.flatMap { (0..<7).contains($0) ? days[$0] : nil } ?? ""
        return " · \(d) \(s.start_time.prefix(5))"
    }

    private func load() async {
        loading = false
        guard !session.offline else {          // offline demo: skip cloud, show a friendly empty state
            classes = DemoData.sections.prefix(2).map {
                Supabase.StudentClass(id: $0.id,
                    course: .init(code: $0.courseCode, title: $0.courseTitle),
                    schedule: [])
            }
            return
        }
        if let a = try? await Supabase.studentAttendance() { present = a.present; total = a.total }
        classes = (try? await Supabase.studentClasses()) ?? []
    }
}
