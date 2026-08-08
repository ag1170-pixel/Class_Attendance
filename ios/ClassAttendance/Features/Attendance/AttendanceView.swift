import SwiftUI

/// The teacher's "Take Attendance" flow: trigger → processing → review → submit.
/// Recognition itself runs server-side (from the classroom camera clip); the app
/// triggers it, then shows the pre-filled tick/cross list for confirmation.
@MainActor
final class AttendanceViewModel: ObservableObject {
    enum Phase { case idle, processing, review, submitted, failed(String) }

    @Published var phase: Phase = .idle
    @Published var rows: [ReviewRow] = []
    @Published var presentCount = 0
    @Published var absentCount = 0

    let section: ClassSection
    private(set) var sessionId: String?

    init(section: ClassSection) { self.section = section }

    /// Trigger: create the session server-side. In the full flow the backend then
    /// pulls the 5s clip and runs recognition; here we poll the review endpoint.
    func takeAttendance() async {
        phase = .processing
        do {
            let resp = try await APIClient.shared.createSession(sectionId: section.id)
            sessionId = resp.sessionId
            // The backend/recognition_bridge runs recognition for this session
            // (webcam/CCTV/clip). Once done, the review is available.
            try await refresh()
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func refresh() async throws {
        guard let sessionId else { return }
        let r = try await APIClient.shared.review(sessionId: sessionId)
        rows = r.rows
        presentCount = r.summary.present
        absentCount = r.summary.absent
    }

    func toggle(_ row: ReviewRow) async {
        guard let sessionId else { return }
        let newStatus: AttendanceStatus = row.status == .present ? .absent : .present
        do {
            try await APIClient.shared.override(sessionId: sessionId,
                                                studentId: row.studentId, status: newStatus)
            try await refresh()
        } catch { phase = .failed(error.localizedDescription) }
    }

    func submit() async {
        guard let sessionId else { return }
        do {
            try await APIClient.shared.submit(sessionId: sessionId)
            phase = .submitted
        } catch { phase = .failed(error.localizedDescription) }
    }
}

struct AttendanceView: View {
    @StateObject private var vm: AttendanceViewModel

    init(section: ClassSection) {
        _vm = StateObject(wrappedValue: AttendanceViewModel(section: section))
    }

    var body: some View {
        Group {
            switch vm.phase {
            case .idle: triggerScreen
            case .processing: processingScreen
            case .review: reviewScreen
            case .submitted: submittedScreen
            case .failed(let msg): failedScreen(msg)
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity))
        .animation(Theme.spring, value: phaseKey)
        .navigationTitle(vm.section.courseCode)
        .navigationBarTitleDisplayMode(.inline)
    }

    // Stable key so SwiftUI animates when the phase case changes.
    private var phaseKey: Int {
        switch vm.phase {
        case .idle: return 0; case .processing: return 1; case .review: return 2
        case .submitted: return 3; case .failed: return 4
        }
    }

    private var triggerScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.viewfinder").font(.system(size: 72)).foregroundStyle(Theme.accent)
            Text("Room \(vm.section.roomCode)").font(.title2.bold())
            Text("Tap to capture 5 seconds from the classroom camera and mark attendance.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Button {
                Task { await vm.takeAttendance() }
            } label: {
                Label("Take Attendance", systemImage: "checkmark.seal")
            }
            .buttonStyle(FilledButton()).padding(.horizontal, 32)
            Spacer()
        }
    }

    private var processingScreen: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.6)
            Text("Recognising faces…").foregroundStyle(.secondary)
        }
    }

    private var reviewScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(vm.presentCount) present", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.present)
                    .contentTransition(.numericText())
                Spacer()
                Label("\(vm.absentCount) absent", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Theme.absent)
                    .contentTransition(.numericText())
            }.font(.subheadline.bold()).padding()
            .animation(Theme.spring, value: vm.presentCount)

            List(vm.rows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.fullName).font(.body)
                        Text(row.registerNo + (row.source == .manualOverride ? " · edited" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let c = row.confidence, row.status == .present {
                        Text(String(format: "%.0f%%", c * 100))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await vm.toggle(row) }
                    } label: {
                        Image(systemName: row.status == .present
                              ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(row.status == .present ? Theme.present : Theme.absent)
                            .font(.title2)
                            .symbolEffect(.bounce, value: row.status)
                    }
                    .buttonStyle(.plain)
                    .animation(Theme.spring, value: row.status)
                }
            }

            Button {
                Task { await vm.submit() }
            } label: {
                Text("Submit Attendance")
            }
            .buttonStyle(FilledButton()).padding()
        }
    }

    private var submittedScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 72))
                .foregroundStyle(Theme.present)
                .symbolEffect(.bounce, value: vm.presentCount)
            Text("Attendance submitted").font(.title2.bold())
            Text("\(vm.presentCount) present · \(vm.absentCount) absent").foregroundStyle(.secondary)
        }
    }

    private func failedScreen(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 56)).foregroundStyle(.orange)
            Text("Something went wrong").font(.headline)
            Text(msg).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Try Again") { Task { await vm.takeAttendance() } }
                .buttonStyle(.bordered)
        }
    }
}
