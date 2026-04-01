import SwiftUI

struct ProcessRowView: View {
    let process: ProcessStats

    var body: some View {
        HStack(spacing: 8) {
            // Process icon
            Image(systemName: "app")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                if !process.locations.isEmpty {
                    Text(process.locations.prefix(2).joined(separator: ", "))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Connection count
            Text("\(process.connectionCount)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
