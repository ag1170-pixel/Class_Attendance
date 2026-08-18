import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var faceIDLock = true
    @State private var reminders = true
    @State private var autoSubmit = false
    @State private var showDeleteConfirm = false
    @State private var showCloudSignIn = false
    @State private var cloudSignedIn = Supabase.isSignedIn

    var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    Toggle("Face ID to open", isOn: $faceIDLock)
                    Toggle("Attendance reminders", isOn: $reminders)
                    Toggle("Auto-submit high confidence", isOn: $autoSubmit)
                }
                Section("Account") {
                    LabeledContent("Signed in", value: "Prof. Rao")
                    LabeledContent("Email", value: "prof@demo.edu")
                }
                Section("Cloud sync") {
                    Label(cloudSignedIn ? "Signed in — attendance syncs to the cloud"
                                        : "Not signed in — submissions will fail",
                          systemImage: cloudSignedIn ? "checkmark.icloud.fill" : "exclamationmark.icloud")
                        .foregroundStyle(cloudSignedIn ? Theme.present : Theme.absent)
                    if cloudSignedIn {
                        Button("Sign out of cloud sync", role: .destructive) {
                            Supabase.signOut(); cloudSignedIn = false
                        }
                    } else {
                        Button("Sign in") { showCloudSignIn = true }
                    }
                }
                Section {
                    NavigationLink { EnrollmentView() } label: {
                        Label("Enroll a student", systemImage: "person.crop.circle.badge.plus")
                    }
                    NavigationLink { CheckInView() } label: {
                        Label("Student check-in (Bluetooth)", systemImage: "wave.3.right")
                    }
                }
                Section("Data Management") {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete All Face Data", systemImage: "trash")
                    }
                }
                Section {
                    Button(role: .destructive) { auth.signOut() } label: {
                        Text("Sign Out").frame(maxWidth: .infinity)
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .confirmationDialog("Are you sure you want to delete all enrolled face data? This cannot be undone.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    FaceRecognizer.shared.deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showCloudSignIn) {
                CloudSignInView { cloudSignedIn = true }
            }
        }
    }
}

/// Teacher sign-in to Supabase — required before attendance can be written to the
/// shared cloud database (see docs/SECURITY_REVIEW.md: writes are scoped to the
/// signed-in teacher's own sections via row-level security).
private struct CloudSignInView: View {
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = "classattendance.teacher@gmail.com"
    @State private var password = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Teacher sign-in") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.absent)
                }
                Button {
                    loading = true; error = nil
                    Task {
                        do {
                            try await Supabase.signIn(email: email, password: password)
                            loading = false; onSuccess(); dismiss()
                        } catch {
                            loading = false
                            self.error = error.localizedDescription
                        }
                    }
                } label: {
                    if loading { ProgressView() } else { Text("Sign in") }
                }
                .disabled(loading || email.isEmpty || password.isEmpty)
            }
            .navigationTitle("Cloud Sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
