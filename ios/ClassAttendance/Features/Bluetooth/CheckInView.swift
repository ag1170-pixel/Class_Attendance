import SwiftUI
import LocalAuthentication

/// Student-side Bluetooth check-in (the other half of the Bluetooth method).
/// The phone advertises the student's register number so the teacher's scanning
/// device can detect it. Gated by Face ID (TrueDepth) so a live person — not a
/// friend holding the phone — has to be present: proximity + a real face = proxy-proof.
/// Keep this screen open during attendance.
struct CheckInView: View {
    @StateObject private var ble = ProximityService()
    @State private var register: String
    @State private var authError = ""
    @FocusState private var editing: Bool

    init(register: String = "RA2411026010081") {
        _register = State(initialValue: register.isEmpty ? "RA2411026010081" : register)
    }

    private var live: Bool { ble.mode == .student }

    /// Require a live Face ID / Touch ID match, THEN start advertising presence.
    private func verifyThenCheckIn() {
        editing = false; authError = ""
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            ble.startStudent(register: register); return   // no biometrics (e.g. simulator) — allow in demo
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "Confirm it's really you to check in") { ok, e in
            DispatchQueue.main.async {
                if ok { ble.startStudent(register: register) }
                else { authError = e?.localizedDescription ?? "Face ID couldn't confirm it's you." }
            }
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: live ? "dot.radiowaves.left.and.right" : "personalhotspot")
                .font(.system(size: 76))
                .foregroundStyle(live ? Theme.present : Theme.accent)
                .symbolEffect(.variableColor.iterative, isActive: live)

            Text(live ? "You're checked in" : "Bluetooth check-in")
                .font(.title2.bold())
            Text(live ? ble.status : "Enter your register number, then confirm with Face ID to check in.")
                .font(.footnote).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if !authError.isEmpty {
                Text(authError).font(.caption).foregroundStyle(Theme.absent)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }

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
                Button { verifyThenCheckIn() } label: {
                    Label("Check in with Face ID", systemImage: "faceid")
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
