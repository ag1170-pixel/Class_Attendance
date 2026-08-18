import SwiftUI

/// Root after login — the four teacher tabs (matches the prototype).
struct MainTabView: View {
    @State private var sel = ProcessInfo.processInfo.arguments.contains("-tab-reports") ? 2 : 0
    var body: some View {
        TabView(selection: $sel) {
            ScheduleView()
                .tabItem { Label("Today", systemImage: "calendar") }.tag(0)
            NavigationStack { MyTimetableView() }
                .tabItem { Label("Timetable", systemImage: "calendar") }.tag(1)
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar") }.tag(2)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }.tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .tint(Theme.accent)
    }
}
