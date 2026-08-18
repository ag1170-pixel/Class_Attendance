import SwiftUI

/// The user's personal timetable — enter each class once (course, room, day, time)
/// and the app tells you your next class + where it is. Stored on the phone.
struct MyTimetableView: View {
    @EnvironmentObject var store: TimetableStore
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                NextClassCard(store: store)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if store.entries.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus").font(.system(size: 34))
                            .foregroundStyle(Theme.accent)
                        Text("Add your classes once").font(.headline)
                        Text("Enter each class with its room and time. We'll tell you your next class and where to go.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            } else {
                ForEach(0..<7, id: \.self) { day in
                    let dayEntries = store.entries(on: day)
                    if !dayEntries.isEmpty {
                        Section(fullDayName(day)) {
                            ForEach(dayEntries) { e in EntryRow(entry: e) }
                                .onDelete { idx in
                                    idx.map { dayEntries[$0] }.forEach(store.remove)
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Timetable")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddClassSheet { store.add($0) }
        }
    }

    private func fullDayName(_ d: Int) -> String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][d]
    }
}

private struct EntryRow: View {
    let entry: TimetableEntry
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.courseCode) · \(entry.courseTitle)").font(.body)
                Label("\(entry.room)\(entry.building.isEmpty ? "" : " · \(entry.building)")",
                      systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Text("\(entry.startTime)–\(entry.endTime)")
                .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
        }
    }
}

/// The payoff: your next upcoming class, where it is, and how long until it starts.
struct NextClassCard: View {
    @ObservedObject var store: TimetableStore
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let next = store.nextClass(from: now) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR NEXT CLASS").font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(next.entry.courseCode) · \(next.entry.courseTitle)")
                        .font(.title3.bold()).foregroundStyle(.white)
                    HStack(spacing: 14) {
                        Label(next.entry.room, systemImage: "door.left.hand.open")
                        if !next.entry.building.isEmpty {
                            Label(next.entry.building, systemImage: "building.2")
                        }
                    }
                    .font(.subheadline).foregroundStyle(.white.opacity(0.95))
                    HStack {
                        Label("\(next.entry.dayName) \(next.entry.startTime)", systemImage: "clock")
                        Spacer()
                        Text(countdownText(minutes: next.minutesUntil))
                            .font(.subheadline.bold())
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    .font(.subheadline).foregroundStyle(.white)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
        .onReceive(tick) { now = $0 }
    }
}

/// Add / enter one class into the personal timetable.
struct AddClassSheet: View {
    let onAdd: (TimetableEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var title = ""
    @State private var room = ""
    @State private var building = ""
    @State private var day = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
    @State private var start = Self.defaultStart
    @State private var end = Self.defaultEnd

    private static let defaultStart: Date = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    private static let defaultEnd: Date = Calendar.current.date(
        bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()

    private var valid: Bool { !code.isEmpty && !room.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Class") {
                    TextField("Course code (e.g. CS301)", text: $code)
                        .textInputAutocapitalization(.characters)
                    TextField("Course title (e.g. Operating Systems)", text: $title)
                }
                Section("Where") {
                    TextField("Room (e.g. A-101)", text: $room)
                    TextField("Building (optional)", text: $building)
                }
                Section("When") {
                    Picker("Day", selection: $day) {
                        ForEach(0..<7, id: \.self) { Text(TimetableEntry.dayNames[$0]).tag($0) }
                    }
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Add Class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(TimetableEntry(
                            courseCode: code, courseTitle: title.isEmpty ? code : title,
                            room: room, building: building, day: day,
                            startTime: Self.hhmm(start), endTime: Self.hhmm(end)))
                        dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }

    private static func hhmm(_ d: Date) -> String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: d), c.component(.minute, from: d))
    }
}
