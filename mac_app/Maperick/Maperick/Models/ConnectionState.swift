import SwiftUI

/// Central state object shared across all views
@Observable
@MainActor
class ConnectionState {
    let monitor = NetworkMonitor()
    let history = HistoryReader()
    let statsStore = StatsStore()

    var totalUniqueIPsEverSeen: Int = 0
    var topHistoricalServers: [AllTimeServerStats] = []

    // Stats for UI
    var dailyStats: [DailyStats] = []
    var weeklySummaries: [PeriodSummary] = []
    var monthlySummaries: [PeriodSummary] = []
    var allTimeSummary: AllTimeSummary?
    var thisWeekSummary: (uniqueIPs: Int, totalConnections: Int) = (0, 0)

    private var historyTimer: Timer?
    private var statsTimer: Timer?

    init() {
        refreshHistoricalData()
        refreshStats()
        startMonitoring()

        historyTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHistoricalData()
            }
        }

        // Refresh stats display every 60 seconds (data is written every 5s via poll)
        statsTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStats()
            }
        }
    }

    func refreshHistoricalData() {
        totalUniqueIPsEverSeen = history.getTotalUniqueIPs()
        topHistoricalServers = history.getTopServers(limit: 5)
    }

    func refreshStats() {
        dailyStats = statsStore.getDailyStats(days: 30)
        weeklySummaries = statsStore.getWeeklySummaries(weeks: 8)
        monthlySummaries = statsStore.getMonthlySummaries(months: 6)
        allTimeSummary = statsStore.getAllTimeSummary()
        thisWeekSummary = statsStore.getThisWeekSummary()
    }

    /// Called after each network poll to record stats
    func recordPollStats() {
        statsStore.recordPoll(servers: monitor.servers, totalConnections: monitor.totalConnections)
    }

    func startMonitoring() {
        monitor.onPollComplete = { [weak self] in
            self?.recordPollStats()
        }
        monitor.start()
    }

    func stopMonitoring() {
        monitor.stop()
        historyTimer?.invalidate()
        historyTimer = nil
        statsTimer?.invalidate()
        statsTimer = nil
    }
}
