import SwiftUI

/// Root after login — the four teacher tabs (matches the prototype).
struct MainTabView: View {
    var body: some View {
        TabView {
            ScheduleView()
                .tabItem { Label("Today", systemImage: "calendar") }
            TimetableView()
                .tabItem { Label("Timetable", systemImage: "square.grid.3x3") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}
