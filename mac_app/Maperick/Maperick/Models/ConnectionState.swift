import SwiftUI

/// Central state object shared across all views
@Observable
@MainActor
class ConnectionState {
    let monitor = NetworkMonitor()
    let history = HistoryReader()

    var totalUniqueIPsEverSeen: Int = 0
    var topHistoricalServers: [AllTimeServerStats] = []

    private var historyTimer: Timer?

    init() {
        refreshHistoricalData()
        startMonitoring()

        historyTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHistoricalData()
            }
        }
    }

    func refreshHistoricalData() {
        totalUniqueIPsEverSeen = history.getTotalUniqueIPs()
        topHistoricalServers = history.getTopServers(limit: 5)
    }

    func startMonitoring() {
        monitor.start()
    }

    func stopMonitoring() {
        monitor.stop()
        historyTimer?.invalidate()
        historyTimer = nil
    }
}
