import Foundation
import SQLite3

// MARK: - History Data Models

struct AllTimeServerStats: Identifiable {
    var id: String { ip }
    let ip: String
    let location: String
    let country: String
    let firstSeen: Date
    let lastSeen: Date
    let timesDetected: Int
    let totalConnections: Int
    let ports: [UInt16]
    let processes: [String]
}

// MARK: - History Reader (reads the Rust app's SQLite database)

class HistoryReader {
    private var db: OpaquePointer?

    init() {
        openDatabase()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        let path = AppConstants.historyDBPath.path
        guard AppConstants.historyDBExists else { return }

        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("[Maperick] Failed to open history database")
            db = nil
        }
    }

    /// Get top N servers by total connections (single query with JOINs to avoid N+1)
    func getTopServers(limit: Int = 10) -> [AllTimeServerStats] {
        guard let db = db else { return [] }

        let query = """
            SELECT c.ip, c.location, c.country, c.first_seen, c.last_seen,
                   c.times_detected, c.total_connections,
                   GROUP_CONCAT(DISTINCT sp.port) AS port_list,
                   GROUP_CONCAT(DISTINCT sproc.name) AS process_list
            FROM connections c
            LEFT JOIN seen_ports sp ON sp.ip = c.ip
            LEFT JOIN seen_processes sproc ON sproc.ip = c.ip
            GROUP BY c.ip
            ORDER BY c.total_connections DESC
            LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [AllTimeServerStats] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let ip = String(cString: sqlite3_column_text(stmt, 0))
            let location = String(cString: sqlite3_column_text(stmt, 1))
            let country = String(cString: sqlite3_column_text(stmt, 2))
            let firstSeen = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
            let lastSeen = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
            let timesDetected = Int(sqlite3_column_int(stmt, 5))
            let totalConnections = Int(sqlite3_column_int64(stmt, 6))

            // Parse ports from GROUP_CONCAT result
            var ports: [UInt16] = []
            if let portText = sqlite3_column_text(stmt, 7) {
                let portString = String(cString: portText)
                ports = portString.split(separator: ",").compactMap { UInt16($0) }.sorted()
            }

            // Parse processes from GROUP_CONCAT result
            var processes: [String] = []
            if let procText = sqlite3_column_text(stmt, 8) {
                let procString = String(cString: procText)
                processes = procString.split(separator: ",").map { String($0) }.sorted()
            }

            results.append(AllTimeServerStats(
                ip: ip,
                location: location,
                country: country,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                timesDetected: timesDetected,
                totalConnections: totalConnections,
                ports: ports,
                processes: processes
            ))
        }

        return results
    }

    /// Get total unique IPs ever seen
    func getTotalUniqueIPs() -> Int {
        guard let db = db else { return 0 }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM connections", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    /// Get stats for a specific IP
    func getStats(for ip: String) -> AllTimeServerStats? {
        guard let db = db else { return nil }

        let query = """
            SELECT ip, location, country, first_seen, last_seen,
                   times_detected, total_connections
            FROM connections WHERE ip = ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, ip, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) == SQLITE_ROW {
            let ip = String(cString: sqlite3_column_text(stmt, 0))
            let location = String(cString: sqlite3_column_text(stmt, 1))
            let country = String(cString: sqlite3_column_text(stmt, 2))
            let firstSeen = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
            let lastSeen = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
            let timesDetected = Int(sqlite3_column_int(stmt, 5))
            let totalConnections = Int(sqlite3_column_int64(stmt, 6))

            return AllTimeServerStats(
                ip: ip,
                location: location,
                country: country,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                timesDetected: timesDetected,
                totalConnections: totalConnections,
                ports: getPorts(for: ip),
                processes: getProcesses(for: ip)
            )
        }

        return nil
    }

    private func getPorts(for ip: String) -> [UInt16] {
        guard let db = db else { return [] }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT port FROM seen_ports WHERE ip = ? ORDER BY port", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, ip, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var ports: [UInt16] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ports.append(UInt16(sqlite3_column_int(stmt, 0)))
        }
        return ports
    }

    private func getProcesses(for ip: String) -> [String] {
        guard let db = db else { return [] }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM seen_processes WHERE ip = ? ORDER BY name", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, ip, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var processes: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            processes.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return processes
    }
}
