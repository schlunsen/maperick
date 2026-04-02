import SwiftUI

struct StatsView: View {
    var state: ConnectionState
    @State private var selectedPeriod: Int = 0 // 0 = week, 1 = month

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Summary cards
                summaryCards

                Divider()
                    .overlay(Color.white.opacity(0.1))

                // Bar chart
                barChartSection

                Divider()
                    .overlay(Color.white.opacity(0.1))

                // Period breakdown
                periodSection
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        let summary = state.allTimeSummary

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ], spacing: 8) {
            StatCard(
                title: "Days Monitored",
                value: "\(summary?.totalDays ?? 0)",
                icon: "calendar",
                color: .blue
            )
            StatCard(
                title: "Unique IPs",
                value: "\(summary?.uniqueIPs ?? 0)",
                icon: "network",
                color: .green
            )
            StatCard(
                title: "Total Connections",
                value: formatNumber(summary?.totalConnections ?? 0),
                icon: "arrow.up.arrow.down",
                color: .orange
            )
            StatCard(
                title: "Peak",
                value: "\(summary?.peakConnections ?? 0)",
                subtitle: summary?.peakDate ?? "",
                icon: "flame.fill",
                color: .red
            )
            StatCard(
                title: "Current Streak",
                value: "\(summary?.currentStreak ?? 0) days",
                icon: "bolt.fill",
                color: .yellow
            )
        }
    }

    // MARK: - Bar Chart

    private var barChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST 30 DAYS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            DailyBarChart(data: state.dailyStats)
                .frame(height: 120)
        }
    }

    // MARK: - Period Breakdown

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("BREAKDOWN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Picker("", selection: $selectedPeriod) {
                    Text("Weekly").tag(0)
                    Text("Monthly").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            let periods = selectedPeriod == 0 ? state.weeklySummaries : state.monthlySummaries

            if periods.isEmpty {
                Text("No data yet — stats accumulate as the app runs")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(periods) { period in
                    PeriodRow(period: period)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000.0)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        }
        return "\(n)"
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Daily Bar Chart

private struct DailyBarChart: View {
    let data: [DailyStats]

    var body: some View {
        Canvas { context, size in
            guard !data.isEmpty else { return }

            let maxValue = max(data.map(\.peakConnections).max() ?? 1, 1)
            let barWidth = max((size.width - CGFloat(data.count - 1) * 2) / CGFloat(data.count), 3)
            let spacing: CGFloat = 2

            for (index, stat) in data.enumerated() {
                let x = CGFloat(index) * (barWidth + spacing)
                let barHeight = max(CGFloat(stat.peakConnections) / CGFloat(maxValue) * size.height, 1)
                let y = size.height - barHeight

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let barColor = chartColor(for: stat.peakConnections, max: maxValue)

                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 2)),
                    with: .color(barColor)
                )
            }
        }
    }

    private func chartColor(for value: Int, max: Int) -> Color {
        let ratio = Double(value) / Double(max)
        if ratio > 0.7 { return .red.opacity(0.8) }
        if ratio > 0.3 { return .yellow.opacity(0.8) }
        return .green.opacity(0.7)
    }
}

// MARK: - Period Row

private struct PeriodRow: View {
    let period: PeriodSummary

    var body: some View {
        HStack(spacing: 12) {
            // Period label
            Text(period.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 120, alignment: .leading)

            // Stats
            HStack(spacing: 16) {
                statChip(icon: "network", value: "\(period.uniqueIPs) IPs", color: .green)
                statChip(icon: "arrow.up.arrow.down", value: formatNumber(period.totalConnections), color: .orange)
                statChip(icon: "flame", value: "Peak \(period.peakConnections)", color: .red)
                if !period.topCountry.isEmpty {
                    statChip(icon: "globe", value: period.topCountry, color: .blue)
                }
                if !period.topProcess.isEmpty {
                    statChip(icon: "app", value: period.topProcess, color: .purple)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func statChip(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000.0)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        }
        return "\(n)"
    }
}
