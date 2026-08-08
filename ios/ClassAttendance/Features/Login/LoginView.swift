import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 66))
                .foregroundStyle(Theme.accent)
                .scaleEffect(pulse ? 1.04 : 1)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            Text("Class Attendance")
                .font(.system(size: 28, weight: .bold))
            Text("Tap Face ID to sign in")
                .foregroundStyle(Theme.dim)

            Spacer()

            Button { auth.authenticate() } label: {
                Label("Sign in with Face ID", systemImage: "lock.open")
            }
            .buttonStyle(FilledButton())
            .padding(.horizontal, 32)

            if let err = auth.lastError {
                Text(err).font(.footnote).foregroundStyle(Theme.absent)
            }
        }
        .padding(.vertical, 40)
        .onAppear { pulse = true }
    }
}
