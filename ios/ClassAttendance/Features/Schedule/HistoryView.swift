import SwiftUI

/// Past attendance sessions — each stored and audit-logged.
struct HistoryView: View {
    var body: some View {
        NavigationStack {
            List(DemoData.history) { s in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(.headline)
                            Text(s.when).font(.subheadline).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(s.present)").font(.title3.bold())
                                .foregroundStyle(Theme.present)
                                .monospacedDigit()
                            Text("of \(s.total)").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    ProgressView(value: Double(s.present), total: Double(s.total))
                        .tint(Theme.present)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .navigationTitle("History")
        }
    }
}
