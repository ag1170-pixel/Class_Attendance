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

                // Demo quick-fill
                HStack(spacing: 10) {
                    demoChip("Teacher", "admin@gmail.com")
                    demoChip("Student", "user@gmail.com")
                }.padding(.top, 2)

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

    private func signIn() async {
        focus = nil
        await session.signIn(email: email, password: password)
    }
}
