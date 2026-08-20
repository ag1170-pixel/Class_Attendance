import SwiftUI

/// Teacher-side Bluetooth attendance (separate method from the camera).
/// Broadcasts/scans, lists nearby students by signal strength, and submits the
/// in-range set to the shared database.
struct BluetoothAttendanceView: View {
    let section: ClassSection
    @StateObject private var ble = ProximityService()
    @State private var submitted = false
    @State private var submitting = false
    @State private var syncFailed = false
    @State private var syncErrorText = ""

    // register -> name, from the class roster (demo roster for now).
    private let names: [String: String] = Dictionary(
        DemoData.review().map { ($0.registerNo, $0.fullName) }, uniquingKeysWith: { a, _ in a })

    private var inRange: [ProximityService.Nearby] {
        ble.nearby.filter { $0.rssi >= ble.rssiThreshold }
    }

    var body: some View {
        Group {
            if submitted {
                submittedView
            } else {
                VStack(spacing: 14) {
                    header
                    rangePicker
                    list
                    submitBar
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Bluetooth · \(section.courseCode)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ble.startTeacher() }
        .onDisappear { ble.stop() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40)).foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative, isActive: !submitted)
            Text(ble.status).font(.subheadline).foregroundStyle(Theme.dim)
            Text("\(inRange.count) in range")
                .font(.title2.bold()).contentTransition(.numericText())
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $ble.rssiThreshold) {
            Text("Near").tag(-65)
            Text("Room").tag(-80)
            Text("Wide").tag(-95)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var list: some View {
        List {
            if ble.nearby.isEmpty {
                Text("Waiting for students to open the app and check in…")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
            ForEach(ble.nearby) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(names[s.register] ?? "Unknown").font(.body)
                        Text(s.register).font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    SignalBars(rssi: s.rssi)
                    Image(systemName: s.rssi >= ble.rssiThreshold ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(s.rssi >= ble.rssiThreshold ? Theme.present : Theme.dim)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var submitBar: some View {
        VStack(spacing: 6) {
            if syncFailed {
                Text(syncErrorText.isEmpty ? "Couldn't reach the cloud database — not recorded. Try again."
                                           : syncErrorText)
                    .font(.footnote).foregroundStyle(Theme.absent)
            }
            Button {
                submitting = true; syncFailed = false
                let present = ble.presentRegisters
                let sectionId = section.id
                Task {
                    do {
                        guard sectionId.count == 36 else {
                            throw Supabase.AuthError(errorDescription:
                                "Open one of your cloud classes (sign in) to save attendance.")
                        }
                        try await Supabase.submitAttendance(sectionId: sectionId, presentRegisters: present)
                        submitting = false; submitted = true
                        ble.stop()
                    } catch {
                        // Don't lie to the teacher: a failed write must NOT show success.
                        submitting = false; syncFailed = true
                        syncErrorText = error.localizedDescription
                    }
                }
            } label: {
                if submitting { ProgressView() }
                else { Label("Submit \(inRange.count) present", systemImage: "checkmark.seal") }
            }
            .buttonStyle(FilledButton())
            .disabled(inRange.isEmpty || submitting)
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
    }

    private var submittedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(Theme.present)
            Text("Attendance submitted").font(.title3.bold())
            Text("\(inRange.count) students marked present via Bluetooth")
                .foregroundStyle(Theme.dim)
        }.padding()
    }
}

/// Little 4-bar signal strength indicator from an RSSI value.
private struct SignalBars: View {
    let rssi: Int
    private var level: Int {   // 0…4
        switch rssi {
        case ..<(-90): return 1
        case ..<(-80): return 2
        case ..<(-70): return 3
        default:       return 4
        }
    }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Theme.accent : Theme.dim.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
    }
}
