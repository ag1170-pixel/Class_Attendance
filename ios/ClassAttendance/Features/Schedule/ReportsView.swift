import SwiftUI

/// Attendance report — every student's %, with the below-75% "shortage" list
/// split out (the university eligibility threshold). This is the "bird's-eye,
/// no-more-manual-admin" view: who's at risk, at a glance.
struct ReportsView: View {
    private var reports: [DemoData.StudentReport] {
        DemoData.reports.sorted { $0.pct < $1.pct }
    }
    private var short: [DemoData.StudentReport] { reports.filter { $0.isShort } }
    private var ok: [DemoData.StudentReport] { reports.filter { !$0.isShort } }
    private var avg: Int {
        reports.isEmpty ? 0 : reports.map(\.pct).reduce(0, +) / reports.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Stat(value: "\(avg)%", label: "Class average", color: Theme.accent)
                        Stat(value: "\(short.count)", label: "Below \(DemoData.minAttendancePercent)%", color: Theme.absent)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if !short.isEmpty {
                    Section("Shortage · below \(DemoData.minAttendancePercent)%") {
                        ForEach(short) { ReportRow(r: $0) }
                    }
                }
                Section("On track · \(DemoData.minAttendancePercent)% and above") {
                    ForEach(ok) { ReportRow(r: $0) }
                }
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: exportText) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }

    private var exportText: String {
        "CS301 · Operating Systems — Attendance report\n\n" +
        reports.map { "\($0.register)  \($0.name)  \($0.attended)/\($0.held)  \($0.pct)%\($0.isShort ? "  SHORT" : "")" }
            .joined(separator: "\n")
    }
}

private struct Stat: View {
    let value: String, label: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 27, weight: .bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct ReportRow: View {
    let r: DemoData.StudentReport
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name)
                Text("\(r.register) · \(r.attended)/\(r.held) classes")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Text("\(r.pct)%")
                .font(.headline).monospacedDigit()
                .foregroundStyle(r.isShort ? Theme.absent : Theme.present)
        }
        .padding(.vertical, 2)
    }
}
