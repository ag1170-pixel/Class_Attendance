import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionManager
    @State private var reminders = true
    @State private var autoSubmit = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in", value: session.name)
                    LabeledContent("Role", value: "Teacher")
                    Label("Attendance syncs to your classes in the cloud",
                          systemImage: "checkmark.icloud.fill")
                        .font(.footnote).foregroundStyle(Theme.present)
                }
                Section("Preferences") {
                    Toggle("Attendance reminders", isOn: $reminders)
                    Toggle("Auto-submit high confidence", isOn: $autoSubmit)
                }
                Section("Students") {
                    NavigationLink { EnrollmentView() } label: {
                        Label("Enroll a student", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                Section("Data management") {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete all face data on this phone", systemImage: "trash")
                    }
                }
                Section {
                    Button(role: .destructive) { session.signOut() } label: {
                        Text("Sign out").frame(maxWidth: .infinity)
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .confirmationDialog("Delete all enrolled face data on this phone? This can't be undone.",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { FaceRecognizer.shared.deleteAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
