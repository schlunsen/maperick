import SwiftUI
import AppKit

/// Hidden NSView that removes the native traffic-light buttons from its window
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Hide native close/minimize/zoom buttons
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            // Make the title bar area transparent and blend with content
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            // Dark background for the title bar area
            window.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1.0)

            // Position window in top-right corner, just below menu bar
            if let screen = window.screen ?? NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowSize = window.frame.size
                let x = screenFrame.maxX - windowSize.width
                let y = screenFrame.maxY - windowSize.height
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct GlobeWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    var state: ConnectionState
    @State private var selectedTab: Int = 0
    @State private var selectedProcess: String? = nil
    @State private var followMode: Bool = false
    @State private var isHoveringClose: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Custom title bar area (window is frameless)
            HStack(spacing: 10) {
                // Close button
                Button(action: {
                    dismissWindow(id: "globe-window")
                }) {
                    Circle()
                        .fill(isHoveringClose ? Color.red : Color.red.opacity(0.7))
                        .frame(width: 13, height: 13)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(isHoveringClose ? .white.opacity(0.9) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringClose = hovering
                }

                Text("Maperick")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                // Filter indicator
                if let proc = selectedProcess {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(proc)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                        Button(action: { selectedProcess = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Follow mode toggle
                Button(action: {
                    followMode.toggle()
                    state.monitor.globeScene.setFollowMode(followMode)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: followMode ? "location.fill" : "location")
                            .font(.system(size: 11))
                        Text("Follow")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(followMode ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .foregroundColor(followMode ? .accentColor : .secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(displayedConnectionCount > 0 ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text("\(displayedConnectionCount) active connections")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(displayedConnectionCount > 0 ? .green : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)))

            Divider()

            // 3D Globe - takes most of the space
            GlobeView(scene: state.monitor.globeScene, allowsInteraction: true, autoRotates: true)
                .frame(minHeight: 400)
                .onAppear {
                    // Zoom out a notch for the big window view
                    state.monitor.globeScene.zoomCamera(toZ: 13)
                }

            Divider()

            // Bottom stats bar
            HStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("Servers").tag(0)
                    Text("Processes").tag(1)
                    Text("History").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 8)

                // Quick stats
                switch selectedTab {
                case 0:
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(filteredServers.prefix(8)) { server in
                                HStack(spacing: 4) {
                                    if !server.countryCode.isEmpty {
                                        Text(server.flagEmoji)
                                    }
                                    Text(server.city.isEmpty ? server.ip : server.city)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Text("\(server.connectionCount)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(intensityColor(server.connectionCount))
                                }
                            }
                        }
                    }
                case 1:
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(state.monitor.processes.prefix(8)) { proc in
                                Button(action: {
                                    if selectedProcess == proc.name {
                                        selectedProcess = nil
                                    } else {
                                        selectedProcess = proc.name
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: selectedProcess == proc.name ? "app.fill" : "app")
                                            .font(.system(size: 9))
                                        Text(proc.name)
                                            .font(.system(size: 11, weight: selectedProcess == proc.name ? .bold : .medium))
                                        Text("\(proc.connectionCount)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(selectedProcess == proc.name ? .accentColor : .secondary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        selectedProcess == proc.name
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.clear
                                    )
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                case 2:
                    HStack(spacing: 16) {
                        Text("\(state.totalUniqueIPsEverSeen) unique IPs all-time")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if !state.topHistoricalServers.isEmpty {
                            ForEach(state.topHistoricalServers.prefix(4)) { hist in
                                HStack(spacing: 4) {
                                    Text(hist.ip)
                                        .font(.system(size: 10, design: .monospaced))
                                    Text("\(hist.totalConnections)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                default:
                    EmptyView()
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 40)
        }
        .frame(minWidth: 700, minHeight: 550)
        .background(WindowAccessor())
        .background(Color(nsColor: NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1.0)))
        .onChange(of: selectedProcess) { _, newValue in
            // Set the process filter on the monitor so it persists across polls
            state.monitor.processFilter = newValue
            // Immediately update the globe
            if let processName = newValue {
                let filtered = state.monitor.servers.filter { $0.processes.contains(processName) }
                state.monitor.globeScene.updateConnections(servers: filtered)
                // Stop rotation and focus the globe on the filtered connections
                state.monitor.globeScene.focusOnServers(filtered)
            } else {
                state.monitor.globeScene.updateConnections(servers: state.monitor.servers)
                // Zoom back out
                state.monitor.globeScene.zoomCamera(toZ: 13)
            }
        }
    }

    private var filteredServers: [ServerInfo] {
        if let proc = selectedProcess {
            return state.monitor.servers.filter { $0.processes.contains(proc) }
        }
        return state.monitor.servers
    }

    private var displayedConnectionCount: Int {
        if selectedProcess != nil {
            return filteredServers.reduce(0) { $0 + $1.connectionCount }
        }
        return state.monitor.totalConnections
    }

    private func intensityColor(_ count: Int) -> Color {
        switch count {
        case 1: return .green
        case 2...5: return .yellow
        default: return .red
        }
    }
}
