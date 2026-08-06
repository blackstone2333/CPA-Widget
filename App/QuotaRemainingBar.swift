import SwiftUI

struct QuotaRemainingBar: View {
    let percentage: Int
    let color: Color

    private var clampedPercentage: Int {
        min(max(percentage, 0), 100)
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(clampedPercentage) / 100
            let fillWidth = proxy.size.width * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))

                if clampedPercentage > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(fillWidth, 4))
                } else {
                    Capsule()
                        .fill(Color.red.opacity(0.82))
                        .frame(width: 4)
                }

                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
            }
        }
        .frame(height: 7)
        .accessibilityElement()
        .accessibilityLabel("\(clampedPercentage)%")
    }
}
