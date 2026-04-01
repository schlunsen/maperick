import Foundation
import Observation

// MARK: - Data Models

struct ConnectionInfo: Identifiable, Hashable {
    let id = UUID()
    let remoteIP: String
    let remotePort: UInt16
    let localPort: UInt16
    let processName: String
    let pid: Int32
    let state: String
}

struct ServerInfo: Identifiable, Hashable {
    var id: String { ip }
    let ip: String
    let city: String
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    var connectionCount: Int
    var ports: [UInt16]
    var processes: [String]
    let flagEmoji: String

    nonisolated init(ip: String, city: String, country: String, countryCode: String,
         latitude: Double, longitude: Double, connectionCount: Int,
         ports: [UInt16], processes: [String]) {
        self.ip = ip
        self.city = city
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.connectionCount = connectionCount
        self.ports = ports
        self.processes = processes
        self.flagEmoji = countryCode
            .unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }
            .joined()
    }

    /// Color based on connection count (matching the TUI color scheme)
    var intensityColor: String {
        switch connectionCount {
        case 1: return "green"
        case 2...5: return "yellow"
        default: return "red"
        }
    }
}

struct ProcessStats: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var connectionCount: Int
    var remoteIPs: [String]
    var locations: [String]
}

// MARK: - Network Monitor

@Observable
@MainActor
class NetworkMonitor {
    var connections: [ConnectionInfo] = []
    var servers: [ServerInfo] = []
    var processes: [ProcessStats] = []
    var totalConnections: Int = 0
    var connectionHistory: [Int] = []

    /// The shared 3D globe scene (updated on each poll)
    let globeScene = GlobeScene()

    /// Process filter — when set, only show connections from this process on the globe
    var processFilter: String? = nil

    private var timer: Timer?
    private var geoIPService: GeoIPService?
    private var userLocation: (latitude: Double, longitude: Double)?
    private var didFetchUserLocation = false

    func start() {
        geoIPService = GeoIPService()

        // Fetch user's public IP and geo-locate it
        fetchUserLocation()

        timer = Timer.scheduledTimer(withTimeInterval: AppConstants.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        // Do an immediate poll
        poll()
    }

    /// Fetch the user's public IP address and resolve it to a location
    private func fetchUserLocation() {
        guard !didFetchUserLocation else { return }
        didFetchUserLocation = true

        Task {
            do {
                let url = URL(string: "https://api.ipify.org?format=text")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let ipString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    await MainActor.run {
                        if let geo = self.geoIPService?.lookup(ipString) {
                            self.userLocation = (latitude: geo.latitude, longitude: geo.longitude)
                            self.globeScene.setUserLocation(latitude: geo.latitude, longitude: geo.longitude)
                            print("[Maperick] User location: \(geo.city), \(geo.country) (\(geo.latitude), \(geo.longitude))")
                        }
                    }
                }
            } catch {
                print("[Maperick] Failed to fetch user public IP: \(error)")
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let geoIP = self.geoIPService
        let currentFilter = self.processFilter

        Task.detached { [weak self] in
            let rawConnections = Self.parseLsof()

            // Use Sets for deduplication during aggregation
            var serverMap: [String: ServerInfo] = [:]
            var serverPortSets: [String: Set<UInt16>] = [:]
            var serverProcessSets: [String: Set<String>] = [:]
            var processMap: [String: ProcessStats] = [:]
            var processIPSets: [String: Set<String>] = [:]
            var processLocSets: [String: Set<String>] = [:]

            for conn in rawConnections {
                let geo = geoIP?.lookup(conn.remoteIP)

                if var server = serverMap[conn.remoteIP] {
                    server.connectionCount += 1
                    var portSet = serverPortSets[conn.remoteIP]!
                    if portSet.insert(conn.remotePort).inserted {
                        server.ports.append(conn.remotePort)
                    }
                    serverPortSets[conn.remoteIP] = portSet
                    if !conn.processName.isEmpty {
                        var procSet = serverProcessSets[conn.remoteIP]!
                        if procSet.insert(conn.processName).inserted {
                            server.processes.append(conn.processName)
                        }
                        serverProcessSets[conn.remoteIP] = procSet
                    }
                    serverMap[conn.remoteIP] = server
                } else {
                    serverMap[conn.remoteIP] = ServerInfo(
                        ip: conn.remoteIP,
                        city: geo?.city ?? "",
                        country: geo?.country ?? "",
                        countryCode: geo?.countryCode ?? "",
                        latitude: geo?.latitude ?? 0,
                        longitude: geo?.longitude ?? 0,
                        connectionCount: 1,
                        ports: [conn.remotePort],
                        processes: conn.processName.isEmpty ? [] : [conn.processName]
                    )
                    serverPortSets[conn.remoteIP] = Set([conn.remotePort])
                    serverProcessSets[conn.remoteIP] = conn.processName.isEmpty ? Set() : Set([conn.processName])
                }

                // Build process stats
                if !conn.processName.isEmpty {
                    if var proc = processMap[conn.processName] {
                        proc.connectionCount += 1
                        var ipSet = processIPSets[conn.processName]!
                        if ipSet.insert(conn.remoteIP).inserted {
                            proc.remoteIPs.append(conn.remoteIP)
                        }
                        processIPSets[conn.processName] = ipSet
                        let loc = geo.map { "\($0.city), \($0.country)" } ?? conn.remoteIP
                        if !loc.isEmpty {
                            var locSet = processLocSets[conn.processName]!
                            if locSet.insert(loc).inserted {
                                proc.locations.append(loc)
                            }
                            processLocSets[conn.processName] = locSet
                        }
                        processMap[conn.processName] = proc
                    } else {
                        let loc = geo.map { "\($0.city), \($0.country)" } ?? conn.remoteIP
                        processMap[conn.processName] = ProcessStats(
                            name: conn.processName,
                            connectionCount: 1,
                            remoteIPs: [conn.remoteIP],
                            locations: loc.isEmpty ? [] : [loc]
                        )
                        processIPSets[conn.processName] = Set([conn.remoteIP])
                        processLocSets[conn.processName] = loc.isEmpty ? Set() : Set([loc])
                    }
                }
            }

            // Sort servers by connection count
            let sortedServers = serverMap.values.sorted { $0.connectionCount > $1.connectionCount }
            let sortedProcesses = processMap.values.sorted { $0.connectionCount > $1.connectionCount }
            let totalCount = rawConnections.count

            // Publish results back on MainActor
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.connections = rawConnections
                self.totalConnections = totalCount
                self.servers = sortedServers
                self.processes = sortedProcesses

                // Track history for sparkline
                self.connectionHistory.append(totalCount)
                self.connectionHistory = Array(self.connectionHistory.suffix(AppConstants.sparklineWindow))

                // Update 3D globe — respect process filter
                if let filter = currentFilter {
                    let filtered = sortedServers.filter { $0.processes.contains(filter) }
                    self.globeScene.updateConnections(servers: filtered)
                } else {
                    self.globeScene.updateConnections(servers: sortedServers)
                }
            }
        }
    }

    /// Parse `lsof -i TCP -P -n` output to get active TCP connections
    nonisolated private static func parseLsof() -> [ConnectionInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "TCP", "-P", "-n"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // suppress errors

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return [] }

            let output = String(data: data, encoding: .utf8) ?? ""
            return parseLsofOutput(output)
        } catch {
            return []
        }
    }

    nonisolated private static func parseLsofOutput(_ output: String) -> [ConnectionInfo] {
        var connections: [ConnectionInfo] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() { // skip header
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9 else { continue }

            let command = String(fields[0])
            let pid = Int32(fields[1]) ?? 0

            // Parse the network address part (fields[8])
            let networkPart = String(fields[8])

            // Format: localIP:localPort->remoteIP:remotePort or *:port (LISTEN)
            guard networkPart.contains("->") else { continue }
            guard !networkPart.contains("(LISTEN)") else { continue }

            let parts = networkPart.components(separatedBy: "->")
            guard parts.count == 2 else { continue }

            let local = parts[0]
            let remote = parts[1].components(separatedBy: " ").first ?? parts[1]

            // Parse remote IP and port
            guard let lastColon = remote.lastIndex(of: ":") else { continue }
            let remoteIP = String(remote[..<lastColon])
            let remotePortStr = String(remote[remote.index(after: lastColon)...])
            guard let remotePort = UInt16(remotePortStr) else { continue }

            // Parse local port
            guard let localLastColon = local.lastIndex(of: ":") else { continue }
            let localPortStr = String(local[local.index(after: localLastColon)...])
            guard let localPort = UInt16(localPortStr) else { continue }

            // Skip localhost, link-local, and IPv6 connections (GeoIP only supports IPv4)
            if remoteIP == "127.0.0.1" || remoteIP == "::1" || remoteIP == "*"
                || remoteIP.hasPrefix("fe80:") || remoteIP.hasPrefix("[fe80:")
                || remoteIP.contains(":") // Skip all IPv6 for now
                || remoteIP.hasPrefix("10.")
                || remoteIP.hasPrefix("192.168.")
                || remoteIP.hasPrefix("172.16.") || remoteIP.hasPrefix("172.17.")
                || remoteIP.hasPrefix("172.18.") || remoteIP.hasPrefix("172.19.")
                || remoteIP.hasPrefix("172.20.") || remoteIP.hasPrefix("172.2")
                || remoteIP.hasPrefix("172.30.") || remoteIP.hasPrefix("172.31.") {
                continue
            }

            // Determine state
            let state = line.contains("(ESTABLISHED)") ? "ESTABLISHED" :
                        line.contains("(CLOSE_WAIT)") ? "CLOSE_WAIT" : "OTHER"

            connections.append(ConnectionInfo(
                remoteIP: remoteIP,
                remotePort: remotePort,
                localPort: localPort,
                processName: command,
                pid: pid,
                state: state
            ))
        }

        return connections
    }
}
