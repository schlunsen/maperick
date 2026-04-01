import SwiftUI

struct ConnectionSparkline: View {
    let data: [Int]
    let color: Color
    let height: CGFloat

    init(data: [Int], color: Color = .green, height: CGFloat = 30) {
        self.data = data
        self.color = color
        self.height = height
    }

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }

            let maxValue = max(data.max() ?? 1, 1)
            let stepX = size.width / CGFloat(data.count - 1)

            // Build path
            var path = Path()
            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height - (CGFloat(value) / CGFloat(maxValue)) * size.height

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Stroke the line
            context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1.5)

            // Fill area under the curve
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()

            context.fill(fillPath, with: .color(color.opacity(0.15)))
        }
        .frame(height: height)
    }
}
