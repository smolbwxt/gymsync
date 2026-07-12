import SwiftUI
import Charts

struct TrendChartView: View {
    @Environment(\.gsTheme) private var theme

    let title: String
    let data: [(Date, Double)]

    var body: some View {
        GSCard(bordered: true) {
            VStack(alignment: .leading, spacing: 10) {
                GSSectionHeader(title)
                if data.isEmpty {
                    Text("Not enough data yet.")
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                } else {
                    Chart(Array(data.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                            .foregroundStyle(theme.accent)
                        PointMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                            .foregroundStyle(theme.accent)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 140)
                }
            }
            .padding(16)
        }
    }
}
