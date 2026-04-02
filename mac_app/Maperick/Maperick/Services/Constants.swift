import Foundation

nonisolated enum AppConstants {
    /// The data directory for maperick (~/Library/Application Support/maperick)
    static let dataDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("maperick", isDirectory: true)
    }()

    /// Path to the GeoIP MMDB database
    static let geoDBPath: URL = {
        dataDir.appendingPathComponent("dbip-city-lite.mmdb")
    }()

    /// Path to the SQLite history database
    static let historyDBPath: URL = {
        dataDir.appendingPathComponent("history.db")
    }()

    /// Whether the GeoIP database exists
    static var geoDBExists: Bool {
        FileManager.default.fileExists(atPath: geoDBPath.path)
    }

    /// Whether the history database exists
    static var historyDBExists: Bool {
        FileManager.default.fileExists(atPath: historyDBPath.path)
    }

    /// Polling interval in seconds for network stats
    static let pollInterval: TimeInterval = 5.0

    /// Maximum number of recent connection counts to track for sparklines
    static let sparklineWindow = 60

    /// Cached result of findMaperickBinary
    private static var _cachedMaperickBinary: String? = nil
    private static var _didSearchBinary = false

    /// Try to find the maperick CLI binary (result is cached)
    static func findMaperickBinary() -> String? {
        if _didSearchBinary {
            return _cachedMaperickBinary
        }

        _didSearchBinary = true

        // Check common locations
        let candidates = [
            "/usr/local/bin/maperick",
            "/opt/homebrew/bin/maperick",
            NSHomeDirectory() + "/.cargo/bin/maperick",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                _cachedMaperickBinary = path
                return path
            }
        }

        // Try `which maperick`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["maperick"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                    _cachedMaperickBinary = path
                    return path
                }
            }
        } catch {}

        return nil
    }
}
