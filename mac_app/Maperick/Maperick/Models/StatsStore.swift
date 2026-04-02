import Foundation
import SQLite3

// MARK: - Data Models

struct DailyStats: Identifiable {
    var id: String { date }
    let date: String              // YYYY-MM-DD
    let totalConnections: Int
    let uniqueIPs: Int
    let peakConnections: Int
    let newIPs: Int
    let topCountry: String
    let topProcess: String
}

struct PeriodSummary: Identifiable {
    var id: String { label }
    let label: String             // e.g. "Mar 2026" or "Mar 9–15"
    let days: Int
    let totalConnections: Int
    let uniqueIPs: Int
    let peakConnections: Int
    let peakDate: String
    let newIPs: Int
    let topCountry: String
    let topProcess: String
}

struct AllTimeSummary {
    let totalDays: Int
    let totalConnections: Int
    let uniqueIPs: Int
    let peakConnections: Int
    let peakDate: String
    let currentStreak: Int
}

// MARK: - StatsStore

/// Writes daily stats and per-IP history to the shared `history.db`.
/// The mac app writes to the same tables the Rust CLI uses (`connections`, `seen_ports`, `seen_processes`)
/// plus a new `daily_stats` table for time-series queries.
class StatsStore {
    private var db: OpaquePointer?

    init() {
        openDatabase()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let dir = AppConstants.dataDir
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = AppConstants.historyDBPath.path

        // Open read-write, create if needed
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            print("[Maperick] StatsStore: failed to open/create history database")
            db = nil
            return
        }

        // WAL mode for concurrent reads (HistoryReader may be reading)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)

        // Create daily_stats table
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS daily_stats (
                date              TEXT PRIMARY KEY,
                total_connections INTEGER NOT NULL DEFAULT 0,
                unique_ips        INTEGER NOT NULL DEFAULT 0,
                peak_connections  INTEGER NOT NULL DEFAULT 0,
                new_ips           INTEGER NOT NULL DEFAULT 0,
                top_country       TEXT NOT NULL DEFAULT '',
                top_process       TEXT NOT NULL DEFAULT ''
            );
            """, nil, nil, nil)

        // Ensure the Rust CLI tables also exist (in case CLI has never run)
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS connections (
                ip              TEXT PRIMARY KEY,
                location        TEXT NOT NULL DEFAULT '',
                country         TEXT NOT NULL DEFAULT '',
                first_seen      INTEGER NOT NULL,
                last_seen       INTEGER NOT NULL,
                times_detected  INTEGER NOT NULL DEFAULT 0,
                total_connections INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS seen_ports (
                ip   TEXT NOT NULL,
                port INTEGER NOT NULL,
                PRIMARY KEY (ip, port)
            );
            CREATE TABLE IF NOT EXISTS seen_processes (
                ip   TEXT NOT NULL,
                name TEXT NOT NULL,
                PRIMARY KEY (ip, name)
            );
            """, nil, nil, nil)
    }

    // MARK: - Write (called each poll ~5s)

    /// Record a poll's worth of data into the daily_stats and connections tables.
    func recordPoll(servers: [ServerInfo], totalConnections: Int) {
        guard let db = db else { return }

        let today = Self.todayString()
        let now = Self.nowEpoch()

        // --- Update daily_stats for today ---
        // Compute top country and top process from this poll
        var countryCounts: [String: Int] = [:]
        var processCounts: [String: Int] = [:]
        for server in servers {
            if !server.country.isEmpty {
                countryCounts[server.country, default: 0] += server.connectionCount
            }
            for proc in server.processes {
                processCounts[proc, default: 0] += server.connectionCount
            }
        }
        let topCountry = countryCounts.sorted { $0.value > $1.value }.first?.key ?? ""
        let topProcess = processCounts.sorted { $0.value > $1.value }.first?.key ?? ""

        let uniqueIPs = servers.count

        // Count new IPs (not yet in connections table)
        var newIPs = 0
        for server in servers {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT 1 FROM connections WHERE ip = ?", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, server.ip, -1, nil)
                if sqlite3_step(stmt) != SQLITE_ROW {
                    newIPs += 1
                }
                sqlite3_finalize(stmt)
            }
        }

        // UPSERT daily_stats
        var stmt: OpaquePointer?
        let upsertSQL = """
            INSERT INTO daily_stats (date, total_connections, unique_ips, peak_connections, new_ips, top_country, top_process)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET
                total_connections = total_connections + ?,
                unique_ips = MAX(unique_ips, ?),
                peak_connections = MAX(peak_connections, ?),
                new_ips = new_ips + ?,
                top_country = CASE WHEN ? != '' THEN ? ELSE daily_stats.top_country END,
                top_process = CASE WHEN ? != '' THEN ? ELSE daily_stats.top_process END
            """
        if sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK {
            // INSERT values
            sqlite3_bind_text(stmt, 1, today, -1, nil)           // date
            sqlite3_bind_int(stmt, 2, Int32(totalConnections))    // total_connections (insert)
            sqlite3_bind_int(stmt, 3, Int32(uniqueIPs))           // unique_ips (insert)
            sqlite3_bind_int(stmt, 4, Int32(totalConnections))    // peak_connections (insert)
            sqlite3_bind_int(stmt, 5, Int32(newIPs))              // new_ips (insert)
            sqlite3_bind_text(stmt, 6, topCountry, -1, nil)       // top_country (insert)
            sqlite3_bind_text(stmt, 7, topProcess, -1, nil)       // top_process (insert)
            // UPDATE values
            sqlite3_bind_int(stmt, 8, Int32(totalConnections))    // total_connections += ?
            sqlite3_bind_int(stmt, 9, Int32(uniqueIPs))           // unique_ips = MAX(...)
            sqlite3_bind_int(stmt, 10, Int32(totalConnections))   // peak_connections = MAX(...)
            sqlite3_bind_int(stmt, 11, Int32(newIPs))             // new_ips += ?
            sqlite3_bind_text(stmt, 12, topCountry, -1, nil)      // top_country (update)
            sqlite3_bind_text(stmt, 13, topCountry, -1, nil)
            sqlite3_bind_text(stmt, 14, topProcess, -1, nil)      // top_process (update)
            sqlite3_bind_text(stmt, 15, topProcess, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // --- Also UPSERT per-IP connections (same as Rust CLI) ---
        for server in servers {
            let ip = server.ip
            let location = server.city
            let country = server.country

            // UPSERT connection
            let connSQL = """
                INSERT INTO connections (ip, location, country, first_seen, last_seen, times_detected, total_connections)
                VALUES (?, ?, ?, ?, ?, 1, ?)
                ON CONFLICT(ip) DO UPDATE SET
                    location = ?,
                    country = ?,
                    first_seen = MIN(connections.first_seen, ?),
                    last_seen = MAX(connections.last_seen, ?),
                    times_detected = connections.times_detected + 1,
                    total_connections = connections.total_connections + ?
                """
            if sqlite3_prepare_v2(db, connSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, ip, -1, nil)
                sqlite3_bind_text(stmt, 2, location, -1, nil)
                sqlite3_bind_text(stmt, 3, country, -1, nil)
                sqlite3_bind_int64(stmt, 4, Int64(now))
                sqlite3_bind_int64(stmt, 5, Int64(now))
                sqlite3_bind_int(stmt, 6, Int32(server.connectionCount))
                // UPDATE values
                sqlite3_bind_text(stmt, 7, location, -1, nil)
                sqlite3_bind_text(stmt, 8, country, -1, nil)
                sqlite3_bind_int64(stmt, 9, Int64(now))
                sqlite3_bind_int64(stmt, 10, Int64(now))
                sqlite3_bind_int(stmt, 11, Int32(server.connectionCount))
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            // INSERT OR IGNORE ports
            for port in server.ports {
                if sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO seen_ports (ip, port) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, ip, -1, nil)
                    sqlite3_bind_int(stmt, 2, Int32(port))
                    sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }

            // INSERT OR IGNORE processes
            for proc in server.processes {
                if sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO seen_processes (ip, name) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, ip, -1, nil)
                    sqlite3_bind_text(stmt, 2, proc, -1, nil)
                    sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }
        }
    }

    // MARK: - Query Methods

    /// Get the last N days of stats (for bar chart)
    func getDailyStats(days: Int = 30) -> [DailyStats] {
        guard let db = db else { return [] }

        var stmt: OpaquePointer?
        let sql = """
            SELECT date, total_connections, unique_ips, peak_connections, new_ips, top_country, top_process
            FROM daily_stats
            ORDER BY date DESC
            LIMIT ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(days))

        var results: [DailyStats] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(DailyStats(
                date: String(cString: sqlite3_column_text(stmt, 0)),
                totalConnections: Int(sqlite3_column_int(stmt, 1)),
                uniqueIPs: Int(sqlite3_column_int(stmt, 2)),
                peakConnections: Int(sqlite3_column_int(stmt, 3)),
                newIPs: Int(sqlite3_column_int(stmt, 4)),
                topCountry: String(cString: sqlite3_column_text(stmt, 5)),
                topProcess: String(cString: sqlite3_column_text(stmt, 6))
            ))
        }
        return results.reversed() // chronological order
    }

    /// Get monthly summaries (last N months)
    func getMonthlySummaries(months: Int = 6) -> [PeriodSummary] {
        guard let db = db else { return [] }

        let sql = """
            SELECT
                SUBSTR(date, 1, 7) AS month,
                COUNT(*) AS days,
                SUM(total_connections) AS total_connections,
                MAX(unique_ips) AS max_unique_ips,
                MAX(peak_connections) AS peak_connections,
                SUM(new_ips) AS new_ips,
                (SELECT d2.date FROM daily_stats d2 WHERE SUBSTR(d2.date, 1, 7) = month ORDER BY d2.peak_connections DESC LIMIT 1) AS peak_date,
                (SELECT d3.top_country FROM daily_stats d3 WHERE SUBSTR(d3.date, 1, 7) = month AND d3.top_country != '' ORDER BY d3.total_connections DESC LIMIT 1) AS top_country,
                (SELECT d4.top_process FROM daily_stats d4 WHERE SUBSTR(d4.date, 1, 7) = month AND d4.top_process != '' ORDER BY d4.total_connections DESC LIMIT 1) AS top_process
            FROM daily_stats
            GROUP BY month
            ORDER BY month DESC
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(months))

        var results: [PeriodSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let monthStr = String(cString: sqlite3_column_text(stmt, 0))
            let label = Self.formatMonth(monthStr)
            let peakDateStr = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
            let topCountry = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            let topProcess = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

            results.append(PeriodSummary(
                label: label,
                days: Int(sqlite3_column_int(stmt, 1)),
                totalConnections: Int(sqlite3_column_int64(stmt, 2)),
                uniqueIPs: Int(sqlite3_column_int(stmt, 3)),
                peakConnections: Int(sqlite3_column_int(stmt, 4)),
                peakDate: Self.formatDateShort(peakDateStr),
                newIPs: Int(sqlite3_column_int(stmt, 5)),
                topCountry: topCountry,
                topProcess: topProcess
            ))
        }
        return results.reversed()
    }

    /// Get weekly summaries (last N weeks)
    func getWeeklySummaries(weeks: Int = 8) -> [PeriodSummary] {
        guard let db = db else { return [] }

        // SQLite: compute ISO week via strftime
        let sql = """
            SELECT
                STRFTIME('%Y-W%W', date) AS week,
                MIN(date) AS week_start,
                MAX(date) AS week_end,
                COUNT(*) AS days,
                SUM(total_connections) AS total_connections,
                MAX(unique_ips) AS max_unique_ips,
                MAX(peak_connections) AS peak_connections,
                SUM(new_ips) AS new_ips,
                (SELECT d2.date FROM daily_stats d2 WHERE STRFTIME('%Y-W%W', d2.date) = week ORDER BY d2.peak_connections DESC LIMIT 1) AS peak_date,
                (SELECT d3.top_country FROM daily_stats d3 WHERE STRFTIME('%Y-W%W', d3.date) = week AND d3.top_country != '' ORDER BY d3.total_connections DESC LIMIT 1) AS top_country,
                (SELECT d4.top_process FROM daily_stats d4 WHERE STRFTIME('%Y-W%W', d4.date) = week AND d4.top_process != '' ORDER BY d4.total_connections DESC LIMIT 1) AS top_process
            FROM daily_stats
            GROUP BY week
            ORDER BY week DESC
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(weeks))

        var results: [PeriodSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let startStr = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let endStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let peakDateStr = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
            let topCountry = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? ""
            let topProcess = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""

            results.append(PeriodSummary(
                label: "\(Self.formatDateShort(startStr)) – \(Self.formatDateShort(endStr))",
                days: Int(sqlite3_column_int(stmt, 3)),
                totalConnections: Int(sqlite3_column_int64(stmt, 4)),
                uniqueIPs: Int(sqlite3_column_int(stmt, 5)),
                peakConnections: Int(sqlite3_column_int(stmt, 6)),
                peakDate: Self.formatDateShort(peakDateStr),
                newIPs: Int(sqlite3_column_int(stmt, 7)),
                topCountry: topCountry,
                topProcess: topProcess
            ))
        }
        return results.reversed()
    }

    /// Get all-time summary
    func getAllTimeSummary() -> AllTimeSummary {
        guard let db = db else {
            return AllTimeSummary(totalDays: 0, totalConnections: 0, uniqueIPs: 0, peakConnections: 0, peakDate: "", currentStreak: 0)
        }

        var totalDays = 0
        var totalConnections = 0
        var peakConnections = 0
        var peakDate = ""
        var uniqueIPs = 0

        // Aggregate from daily_stats
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, """
            SELECT COUNT(*), COALESCE(SUM(total_connections), 0), COALESCE(MAX(peak_connections), 0),
                   (SELECT date FROM daily_stats ORDER BY peak_connections DESC LIMIT 1)
            FROM daily_stats
            """, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalDays = Int(sqlite3_column_int(stmt, 0))
                totalConnections = Int(sqlite3_column_int64(stmt, 1))
                peakConnections = Int(sqlite3_column_int(stmt, 2))
                peakDate = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            }
            sqlite3_finalize(stmt)
        }

        // Unique IPs from connections table
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM connections", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                uniqueIPs = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        // Compute current streak (consecutive days with data ending today)
        let streak = computeStreak()

        return AllTimeSummary(
            totalDays: totalDays,
            totalConnections: totalConnections,
            uniqueIPs: uniqueIPs,
            peakConnections: peakConnections,
            peakDate: Self.formatDateShort(peakDate),
            currentStreak: streak
        )
    }

    /// Get this week's summary for the popover
    func getThisWeekSummary() -> (uniqueIPs: Int, totalConnections: Int) {
        guard let db = db else { return (0, 0) }

        // Get start of current week (Monday)
        let today = Self.todayDate()
        let calendar = Calendar(identifier: .iso8601)
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return (0, 0)
        }
        let weekStartStr = Self.dateFormatter().string(from: weekStart)

        var stmt: OpaquePointer?
        var uniqueIPs = 0
        var totalConns = 0

        if sqlite3_prepare_v2(db, """
            SELECT COALESCE(SUM(total_connections), 0), MAX(unique_ips)
            FROM daily_stats WHERE date >= ?
            """, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, weekStartStr, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalConns = Int(sqlite3_column_int64(stmt, 0))
                uniqueIPs = Int(sqlite3_column_int(stmt, 1))
            }
            sqlite3_finalize(stmt)
        }

        return (uniqueIPs, totalConns)
    }

    // MARK: - Private Helpers

    private func computeStreak() -> Int {
        guard let db = db else { return 0 }

        // Get all dates with data, ordered descending
        var stmt: OpaquePointer?
        var dates: [String] = []
        if sqlite3_prepare_v2(db, "SELECT date FROM daily_stats ORDER BY date DESC", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                dates.append(String(cString: sqlite3_column_text(stmt, 0)))
            }
            sqlite3_finalize(stmt)
        }

        guard !dates.isEmpty else { return 0 }

        let today = Self.todayString()
        let calendar = Calendar(identifier: .iso8601)
        let fmt = Self.dateFormatter()

        // Streak must include today or yesterday
        guard let firstDate = fmt.date(from: dates[0]),
              let todayDate = fmt.date(from: today) else { return 0 }

        let daysDiff = calendar.dateComponents([.day], from: firstDate, to: todayDate).day ?? 0
        guard daysDiff <= 1 else { return 0 }

        var streak = 1
        for i in 1..<dates.count {
            guard let current = fmt.date(from: dates[i]),
                  let prev = fmt.date(from: dates[i - 1]) else { break }
            let diff = calendar.dateComponents([.day], from: current, to: prev).day ?? 0
            if diff == 1 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    // MARK: - Date Helpers

    private static func todayString() -> String {
        dateFormatter().string(from: Date())
    }

    private static func todayDate() -> Date { Date() }

    private static func nowEpoch() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private static func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// Format "2026-03" → "Mar 2026"
    private static func formatMonth(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return iso }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard month >= 1 && month <= 12 else { return iso }
        return "\(months[month]) \(parts[0])"
    }

    /// Format "2026-03-15" → "Mar 15"
    private static func formatDateShort(_ iso: String) -> String {
        guard iso.count >= 10 else { return iso }
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]) else { return iso }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard month >= 1 && month <= 12 else { return iso }
        return "\(months[month]) \(parts[2])"
    }
}
