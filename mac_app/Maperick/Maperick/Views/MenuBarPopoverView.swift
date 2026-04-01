import SwiftUI

struct MenuBarPopoverView: View {
    var state: ConnectionState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Mini 3D Globe
            GlobeView(scene: state.monitor.globeScene, allowsInteraction: true)
                .frame(width: 280, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(8)

            // Open Full Globe Button
            Button(action: {
                openWindow(id: "globe-window")
                // Bring app to front since it's an LSUIElement (no dock icon)
                NSApp.activate(ignoringOtherApps: true)
                // Auto-close the menu bar popover
                dismiss()
            }) {
                HStack {
                    Image(systemName: "globe")
                    Text("Open Full Globe")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.7))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            Divider()

            // Servers section
            if !state.monitor.servers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOP SERVERS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(state.monitor.servers.prefix(5)) { server in
                        ServerRowView(server: server)
                    }
                }

                Divider()
                    .padding(.top, 4)
            }

            // Processes section
            if !state.monitor.processes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROCESSES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(state.monitor.processes.prefix(4)) { proc in
                        ProcessRowView(process: proc)
                    }
                }

                Divider()
                    .padding(.top, 4)
            }

            // History section
            if state.totalUniqueIPsEverSeen > 0 {
                HStack {
                    Text("All-time: \(state.totalUniqueIPsEverSeen) unique IPs")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Divider()
            }

            // Bottom actions
            HStack {
                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(.accentColor)
                .font(.system(size: 14, weight: .semibold))

            Text("Maperick")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // Connection count badge
            HStack(spacing: 4) {
                Circle()
                    .fill(state.monitor.totalConnections > 0 ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)

                Text("\(state.monitor.totalConnections) active")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(state.monitor.totalConnections > 0 ? .green : .secondary)
            }
        }
    }

}
