import SwiftUI

/// Shared sign-in for both roles. The signed-in account decides where you land:
/// a teacher gets the teacher app, a student gets the student app.
struct LoginView: View {
    @EnvironmentObject var session: SessionManager
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    enum Field { case email, password }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.16), Color(.systemBackground)],
                           startPoint: .top, endPoint: .center).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.system(size: 54)).foregroundStyle(Theme.accent)
                    Text("Class Attendance").font(.system(size: 28, weight: .bold))
                    Text("Sign in to continue").foregroundStyle(Theme.dim)
                }

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next).onSubmit { focus = .password }
                        .padding(14).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    SecureField("Password", text: $password)
                        .textContentType(.password).focused($focus, equals: .password)
                        .submitLabel(.go).onSubmit { Task { await signIn() } }
                        .padding(14).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 28)

                if let err = session.error {
                    Text(err).font(.footnote).foregroundStyle(Theme.absent)
                        .multilineTextAlignment(.center).padding(.horizontal, 28)
                }

                Button { Task { await signIn() } } label: {
                    if session.busy { ProgressView().tint(.white) }
                    else { Text("Sign in").frame(maxWidth: .infinity) }
                }
                .buttonStyle(FilledButton())
                .disabled(session.busy || email.isEmpty || password.isEmpty)
                .padding(.horizontal, 28)

                // Demo quick-fill (fills the fields for a real cloud sign-in)
                HStack(spacing: 10) {
                    demoChip("Teacher", "admin@gmail.com")
                    demoChip("Student", "user@gmail.com")
                }.padding(.top, 2)

                // Offline entry — skips the network entirely (use if sign-in times out).
                VStack(spacing: 8) {
                    Text("or continue offline").font(.caption).foregroundStyle(Theme.dim)
                    HStack(spacing: 12) {
                        offlineButton("Teacher", systemImage: "person.fill",
                                      role: .teacher(name: "Prof. Rao"))
                        offlineButton("Student", systemImage: "graduationcap.fill",
                                      role: .student(name: "Aditya Gupta",
                                                     register: "RA2411026010081",
                                                     studentId: "a0000006-0000-0000-0000-000000000006"))
                    }
                }
                .padding(.top, 6).padding(.horizontal, 28)

                Spacer(); Spacer()
            }
        }
    }

    private func demoChip(_ label: String, _ mail: String) -> some View {
        Button {
            email = mail; password = "1234"; focus = nil
        } label: {
            Text("Demo · \(label)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.surface2, in: Capsule())
                .foregroundStyle(Theme.accent)
        }
    }

    private func offlineButton(_ label: String, systemImage: String,
                               role: Supabase.Role) -> some View {
        Button { session.enterOffline(as: role) } label: {
            Label("Continue as \(label)", systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)
        }
    }

    private func signIn() async {
        focus = nil
        await session.signIn(email: email, password: password)
    }
}
