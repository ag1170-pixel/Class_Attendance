import SwiftUI

/// Student-side Bluetooth check-in (the other half of the Bluetooth method).
/// The phone advertises the student's register number so the teacher's scanning
/// device can detect it. Keep this screen open during attendance.
struct CheckInView: View {
    @StateObject private var ble = ProximityService()
    @State private var register = "RA2411026010081"   // demo default (Aditya)
    @FocusState private var editing: Bool

    private var live: Bool { ble.mode == .student }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: live ? "dot.radiowaves.left.and.right" : "personalhotspot")
                .font(.system(size: 76))
                .foregroundStyle(live ? Theme.present : Theme.accent)
                .symbolEffect(.variableColor.iterative, isActive: live)

            Text(live ? "You're checked in" : "Bluetooth check-in")
                .font(.title2.bold())
            Text(live ? ble.status : "Enter your register number and tap check in when class starts.")
                .font(.footnote).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            TextField("Register No", text: $register)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .disabled(live)
                .focused($editing)
                .padding(.horizontal, 40)

            Spacer()

            if live {
                Text("Keep this screen open until the teacher finishes.")
                    .font(.caption).foregroundStyle(Theme.dim)
                Button(role: .destructive) { ble.stop() } label: {
                    Text("Stop check-in").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).padding(.horizontal, 24)
            } else {
                Button { editing = false; ble.startStudent(register: register) } label: {
                    Label("Check in", systemImage: "wave.3.right")
                }
                .buttonStyle(FilledButton())
                .disabled(register.isEmpty)
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 30)
        .navigationTitle("Check in")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { ble.stop() }
    }
}
