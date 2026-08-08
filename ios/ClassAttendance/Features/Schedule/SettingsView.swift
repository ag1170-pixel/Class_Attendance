import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var faceIDLock = true
    @State private var reminders = true
    @State private var autoSubmit = false

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
                Section {
                    NavigationLink { EnrollmentView() } label: {
                        Label("Enroll a student", systemImage: "person.crop.circle.badge.plus")
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
        }
    }
}
