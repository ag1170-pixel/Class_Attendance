import Foundation
import LocalAuthentication

/// Biometric unlock for the teacher (Face ID / Touch ID) + simple session state.
/// In production the successful biometric unlock releases an SSO/JWT token stored
/// in the Keychain; here it just gates access and sets the demo user id.
@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var teacherName = ""
    @Published var lastError: String?

    /// Demo teacher id — matches a seeded app_user id you pass in at build time.
    private let demoTeacherId: String
    private let demoTeacherName: String
    private let backendURL: URL

    init(teacherId: String, teacherName: String, backendURL: URL) {
        self.demoTeacherId = teacherId
        self.demoTeacherName = teacherName
        self.backendURL = backendURL
        // UI-test / demo hook: launch with `-autologin` to skip biometric auth.
        if ProcessInfo.processInfo.arguments.contains("-autologin") {
            finishLogin()
        }
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?
        let reason = "Unlock Class Attendance"

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics/passcode available (e.g. plain simulator) — allow in demo.
            finishLogin()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, err in
            Task { @MainActor in
                if ok {
                    self.finishLogin()
                } else {
                    self.lastError = err?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }

    private func finishLogin() {
        teacherName = demoTeacherName
        isAuthenticated = true
        Task { await APIClient.shared.configure(baseURL: backendURL, userId: demoTeacherId) }
    }

    func signOut() {
        isAuthenticated = false
    }
}
