import SwiftUI

struct LiveStatsView: View {
    let stats: RouteStats

    var body: some View {
        HStack(spacing: 0) {
            statCell(
                value: String(format: "%.1f", stats.speedMph),
                unit: "mph",
                icon: "speedometer"
            )
            Divider().frame(height: 32)
            statCell(
                value: String(format: "%.0f°", stats.course),
                unit: "course",
                icon: "arrow.up.circle"
            )
            Divider().frame(height: 32)
            statCell(
                value: formatDistance(stats.odometer),
                unit: "travelled",
                icon: "figure.walk"
            )
            Divider().frame(height: 32)
            statCell(
                value: String(format: "%.0f%%", stats.progress * 100),
                unit: "complete",
                icon: "percent"
            )
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground).opacity(0.01))
    }

    private func statCell(value: String, unit: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).bold())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDistance(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.2fkm", m / 1000) }
        return String(format: "%.0fm", m)
    }
}

#Preview {
    LiveStatsView(stats: RouteStats(
        speedMps: 13.4,
        course: 245,
        odometer: 3400,
        totalDistance: 10000,
        elapsed: 254,
        progress: 0.34,
        eta: 493
    ))
}
