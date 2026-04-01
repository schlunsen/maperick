import SwiftUI

struct ServerRowView: View {
    let server: ServerInfo

    var body: some View {
        HStack(spacing: 8) {
            // Country flag or globe icon
            if !server.countryCode.isEmpty {
                Text(server.flagEmoji)
                    .font(.system(size: 14))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                // City name or IP
                if !server.city.isEmpty {
                    Text(server.city)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                } else {
                    Text(server.ip)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }

                // Country + IP
                HStack(spacing: 4) {
                    if !server.country.isEmpty {
                        Text(server.country)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Text(server.ip)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .lineLimit(1)
            }

            Spacer()

            // Connection count with color indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(intensityColor)
                    .frame(width: 6, height: 6)

                Text("\(server.connectionCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(intensityColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private var intensityColor: Color {
        switch server.connectionCount {
        case 1: return .green
        case 2...5: return .yellow
        default: return .red
        }
    }
}
