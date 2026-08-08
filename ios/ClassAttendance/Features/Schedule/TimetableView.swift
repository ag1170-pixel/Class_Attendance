import SwiftUI

/// Weekly timetable — set once, then it shows what's next and where.
struct TimetableView: View {
    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    @State private var selected = DemoData.today

    private var classesForDay: [ClassSection] {
        DemoData.sections.filter { $0.day == selected }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { d in
                        Button { selected = d } label: {
                            Text(d)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(selected == d ? Theme.accent : Theme.surface2,
                                            in: RoundedRectangle(cornerRadius: 11))
                                .foregroundStyle(selected == d ? .white : Theme.dim)
                                .overlay(alignment: .bottom) {
                                    if d == DemoData.today {
                                        Circle().frame(width: 4, height: 4)
                                            .foregroundStyle(selected == d ? .white : Theme.dim)
                                            .padding(.bottom, 5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.top, 8)

                List {
                    if classesForDay.isEmpty {
                        Text("No classes on \(selected).")
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity).listRowSeparator(.hidden)
                    }
                    ForEach(classesForDay) { c in
                        NavigationLink(value: c) {
                            ClassRow(section: c, showNow: selected == DemoData.today)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Timetable")
            .navigationDestination(for: ClassSection.self) { AttendanceView(section: $0) }
        }
    }
}

/// Shared row used by Today + Timetable.
struct ClassRow: View {
    let section: ClassSection
    var showNow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(section.courseCode) · \(section.courseTitle)")
                    .font(.headline)
                if showNow && section.isNow {
                    Text("Now").font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
            Text("\(section.building ?? "") · Room \(section.roomCode) · \(section.startTime)–\(section.endTime) · \(section.studentCount) students")
                .font(.subheadline).foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 4)
    }
}
