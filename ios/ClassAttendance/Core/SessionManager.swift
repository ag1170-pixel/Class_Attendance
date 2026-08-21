import SwiftUI

/// Who's signed in and what role they have. Drives the whole app's routing:
/// teacher → the professional teacher app; student → the student app.
@MainActor
final class SessionManager: ObservableObject {
    @Published var role: Supabase.Role?
    @Published var busy = false
    @Published var error: String?

    var isSignedIn: Bool { role != nil }

    var name: String {
        switch role {
        case .teacher(let n): return n
        case .student(let n, _, _): return n
        case nil: return ""
        }
    }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    var isTeacher: Bool { if case .teacher = role { return true }; return false }
    var studentRegister: String? { if case .student(_, let r, _) = role { return r }; return nil }
    var studentId: String? { if case .student(_, _, let id) = role { return id }; return nil }

    /// Restore a stored session on launch (silent).
    func restore() async {
        await Supabase.restoreSession()
        if Supabase.isSignedIn { role = await Supabase.currentRole() }
    }

    func signIn(email: String, password: String) async {
        busy = true; error = nil
        do {
            try await Supabase.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                      password: password)
            role = await Supabase.currentRole()
            if role == nil {
                error = "This account isn't set up as a teacher or student yet."
                Supabase.signOut()
            }
        } catch {
            self.error = (error as? Supabase.AuthError)?.errorDescription ?? error.localizedDescription
        }
        busy = false
    }

    func signOut() {
        Supabase.signOut()
        role = nil
    }
}
