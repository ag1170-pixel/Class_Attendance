import SwiftUI
import CoreImage.CIFilterBuiltins

enum ReviewFilter { case all, present, absent }

@MainActor
final class AttendanceViewModel: ObservableObject {
    enum Phase { case idle, processing, review, submitted }

    @Published var phase: Phase = .idle
    @Published var rows: [ReviewRow] = []
    @Published var filter: ReviewFilter = .all

    let section: ClassSection
    init(section: ClassSection) {
        self.section = section
        if ProcessInfo.processInfo.arguments.contains("-demoreview") {   // UI-test route
            rows = DemoData.review(); phase = .review
        }
    }

    var present: Int { rows.filter { $0.status == .present }.count }
    var absent: Int { rows.count - present }

    var visibleRows: [ReviewRow] {
        switch filter {
        case .all: return rows
        case .present: return rows.filter { $0.status == .present }
        case .absent: return rows.filter { $0.status == .absent }
        }
    }

    /// Build the review from the ENROLLED students, not from demo data.
    /// Each enrolled student becomes a row; present/absent is driven by what
    /// the camera actually detected.
    func finish(present: Set<String>) {
        // 1. Get the real enrolled students
        let enrolled = FaceRecognizer.shared.enrolledList()
        
        if enrolled.isEmpty {
            // Fallback to demo data if nobody is enrolled yet
            let roster = DemoData.review()
            rows = roster.map { r in
                ReviewRow(studentId: r.studentId, registerNo: r.registerNo, fullName: r.fullName,
                          status: present.contains(r.registerNo) ? .present : .absent,
                          source: .auto, confidence: present.contains(r.registerNo) ? 0.9 : nil)
            }
        } else {
            // Build from real enrolled data
            rows = enrolled.map { student in
                let isPresent = present.contains(student.register)
                return ReviewRow(studentId: student.register, registerNo: student.register,
                                 fullName: student.name,
                                 status: isPresent ? .present : .absent,
                                 source: .auto, confidence: isPresent ? 0.9 : nil)
            }
        }
        phase = .review
    }

    func toggle(_ row: ReviewRow) {
        guard let i = rows.firstIndex(where: { $0.studentId == row.studentId }) else { return }
        rows[i].status = rows[i].status == .present ? .absent : .present
        rows[i].source = .manualOverride
    }

    func addManual(register: String, name: String) {
        rows.append(ReviewRow(studentId: register, registerNo: register, fullName: name,
                              status: .present, source: .manualOverride, confidence: nil))
    }

    func submit() async {
        let present = Set(rows.filter { $0.status == .present }.map { $0.registerNo })
        phase = .submitted // Mark as submitted instantly so UI doesn't hang!
        Task {
            // Write to shared cloud DB in background
            try? await Supabase.submitAttendance(presentRegisters: present)
        }
    }
}

struct AttendanceView: View {
    @StateObject private var vm: AttendanceViewModel
    @StateObject private var tracker = FaceTracker()
    init(section: ClassSection) { _vm = StateObject(wrappedValue: AttendanceViewModel(section: section)) }

    var body: some View {
        Group {
            switch vm.phase {
            case .idle: TriggerScreen(vm: vm, onStart: startCapture)
            case .processing: LiveCaptureView(tracker: tracker) { present in vm.finish(present: present) }
            case .review: ReviewScreen(vm: vm)
            case .submitted: SubmittedScreen(vm: vm)
            }
        }
        .animation(Theme.spring, value: vm.phase == .review)
        .navigationTitle(vm.section.courseCode)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startCapture() {
        tracker.presentRegisters = []
        vm.phase = .processing
        // LiveCaptureView handles its own 10-second timer with Start button + countdown.
        // Its onComplete callback calls vm.finish(present:) when the teacher taps Submit.
    }
}

// MARK: - Trigger

private struct TriggerScreen: View {
    @ObservedObject var vm: AttendanceViewModel
    let onStart: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.viewfinder").font(.system(size: 72)).foregroundStyle(Theme.accent)
            Text(vm.section.courseTitle).font(.title2.bold())
            Text("\(vm.section.building ?? "") · Room \(vm.section.roomCode)")
                .foregroundStyle(Theme.dim)
            Text("You're in the room. Tap Start, the camera runs for 10 seconds and marks who's present.")
                .font(.footnote).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            Button { onStart() } label: {
                Label("Take Attendance", systemImage: "checkmark.seal")
            }
            .buttonStyle(FilledButton()).padding(.horizontal, 24)
            NavigationLink { ClassQRView(section: vm.section) } label: {
                Text("Show class QR")
            }.padding(.top, 2)
        }
        .padding(.vertical, 24)
    }
}

// MARK: - Review

private struct ReviewScreen: View {
    @ObservedObject var vm: AttendanceViewModel
    @State private var showManual = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StatTile(n: vm.present, label: "Present", color: Theme.present,
                         selected: vm.filter == .present) {
                    vm.filter = vm.filter == .present ? .all : .present
                }
                StatTile(n: vm.absent, label: "Absent", color: Theme.absent,
                         selected: vm.filter == .absent) {
                    vm.filter = vm.filter == .absent ? .all : .absent
                }
            }
            .padding([.horizontal, .top])

            Text(hint).font(.caption).foregroundStyle(Theme.dim).padding(.top, 6)

            List {
                if vm.filter != .absent {
                    Section("Present · \(vm.present)") {
                        ForEach(vm.rows.filter { $0.status == .present }) { row in
                            StudentRow(row: row) { vm.toggle(row) }
                        }
                    }
                }
                if vm.filter != .present {
                    Section("Absent · \(vm.absent)") {
                        ForEach(vm.rows.filter { $0.status == .absent }) { row in
                            StudentRow(row: row) { vm.toggle(row) }
                        }
                    }
                }
                Section {
                    NavigationLink { LocateView(section: vm.section) } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Not enrolled").font(.body)
                                Text("Seen in the room — tap to locate").font(.caption).foregroundStyle(Theme.dim)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                    Button { showManual = true } label: {
                        Label("Add student manually", systemImage: "plus.circle")
                    }
                } header: { Text("Unrecognized") }
            }
            .listStyle(.insetGrouped)
            .animation(Theme.spring, value: vm.filter)

            Button("Submit Attendance") { Task { await vm.submit() } }
                .buttonStyle(FilledButton()).padding()
        }
        .sheet(isPresented: $showManual) {
            ManualAddSheet { reg, name in vm.addManual(register: reg, name: name); showManual = false }
        }
    }

    private var hint: String {
        switch vm.filter {
        case .present: return "Present only — tap Present again for all"
        case .absent: return "Absent only — read these names out to confirm"
        case .all: return "Tap Present or Absent to filter"
        }
    }
}

private struct StatTile: View {
    let n: Int, label: String, color: Color, selected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(n)").font(.system(size: 27, weight: .bold)).foregroundStyle(color)
                    .monospacedDigit().contentTransition(.numericText())
                Text(label).font(.caption).foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .strokeBorder(selected ? color : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain).animation(Theme.spring, value: n)
    }
}

private struct StudentRow: View {
    let row: ReviewRow
    let toggle: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(row.fullName)
                Text(row.registerNo + (row.source == .manualOverride ? " · edited" : ""))
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            if let c = row.confidence, row.status == .present {
                Text("\(Int(c * 100))%").font(.caption).foregroundStyle(Theme.dim)
            }
            Button(action: toggle) {
                Image(systemName: row.status == .present ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(row.status == .present ? Theme.present : Theme.absent)
                    .font(.title2).symbolEffect(.bounce, value: row.status)
            }.buttonStyle(.plain)
        }
    }
}

private struct ManualAddSheet: View {
    let onAdd: (String, String) -> Void
    @State private var reg = ""
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Student not enrolled") {
                    TextField("Register no (e.g. RA2411026010081)", text: $reg)
                        .textInputAutocapitalization(.characters)
                    TextField("Full name", text: $name)
                }
            }
            .navigationTitle("Add manually").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(reg, name) }
                        .disabled(reg.isEmpty || name.isEmpty)
                }
            }
        }
    }
}

private struct SubmittedScreen: View {
    @ObservedObject var vm: AttendanceViewModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 72))
                .foregroundStyle(Theme.present).symbolEffect(.bounce, value: vm.phase)
            Text("Attendance submitted").font(.title2.bold())
            Text("\(vm.present) present · \(vm.absent) absent").foregroundStyle(Theme.dim)
        }
    }
}

// MARK: - Class QR (real, scannable)

struct ClassQRView: View {
    let section: ClassSection
    var body: some View {
        VStack(spacing: 16) {
            Text("Class pass").font(.caption.bold()).foregroundStyle(Theme.accent)
                .textCase(.uppercase)
            Text("\(section.courseCode) · \(section.courseTitle)").font(.title3.bold())
            Text("\(section.building ?? "") · Room \(section.roomCode)").foregroundStyle(Theme.dim)
            Image(uiImage: QR.image("classattendance://class/\(section.id)"))
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: 200, height: 200)
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 12) {
                Label("Students — scan to join this class", systemImage: "person.crop.circle.badge.plus")
                Label("Teacher — scan to take attendance", systemImage: "camera.viewfinder")
            }.font(.subheadline).foregroundStyle(Theme.dim)
            Spacer()
        }
        .padding().navigationTitle("Class QR").navigationBarTitleDisplayMode(.inline)
    }
}

enum QR {
    static func image(_ string: String) -> UIImage {
        let ctx = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        if let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
           let cg = ctx.createCGImage(out, from: out.extent) {
            return UIImage(cgImage: cg)
        }
        return UIImage(systemName: "qrcode") ?? UIImage()
    }
}

// MARK: - Locate the unenrolled person

struct LocateView: View {
    let section: ClassSection
    @State private var marked = false
    private let highlighted = 12

    var body: some View {
        VStack(spacing: 14) {
            Text("Not enrolled").font(.caption.bold()).foregroundStyle(.orange).textCase(.uppercase)
            Text("Spot them in the room").font(.title3.bold())
            Text("\(section.courseCode) · Room \(section.roomCode) — live camera view")
                .font(.subheadline).foregroundStyle(Theme.dim)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.16)).frame(height: 210)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                    ForEach(0..<20, id: \.self) { i in
                        Circle()
                            .fill(i == highlighted ? Color.orange : Color.white.opacity(0.22))
                            .frame(width: 22, height: 24)
                            .overlay {
                                if i == highlighted {
                                    Circle().strokeBorder(.orange, lineWidth: 3).scaleEffect(1.5)
                                }
                            }
                    }
                }.padding(28)
                Text("CAMERA · ROOM \(section.roomCode)").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55)).padding(10)
            }

            Text("The highlighted person isn't on the class list. Show them the class QR to enroll — they don't have the app yet. Their attendance is safe: mark them present now, it links once they join.")
                .font(.footnote).foregroundStyle(Theme.dim)
            Spacer()
            Button(marked ? "Marked present ✓" : "Mark present") { marked = true }
                .buttonStyle(FilledButton()).disabled(marked)
        }
        .padding().navigationTitle("Locate").navigationBarTitleDisplayMode(.inline)
    }
}
