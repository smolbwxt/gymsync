import SwiftUI
import Charts

struct TrendChartView: View {
    let title: String
    let data: [(Date, Double)]

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            if data.isEmpty {
                Text("Not enough data yet.")
                    .foregroundStyle(.secondary).font(.caption)
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                    PointMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                }
                .frame(height: 200)
            }
        }
        .padding()
    }
}
