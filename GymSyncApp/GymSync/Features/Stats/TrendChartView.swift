import SwiftUI
import Charts

// Canvas: time-range toggle for the trend chart — 8 weeks / 6 months / 1 year.
enum TrendRange: String, CaseIterable, Identifiable {
    case eightWeeks = "8w"
    case sixMonths = "6m"
    case oneYear = "1y"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .eightWeeks: return 56
        case .sixMonths: return 182
        case .oneYear: return 365
        }
    }
}

struct TrendChartView: View {
    @Environment(\.gsTheme) private var theme

    let title: String
    /// Full, unfiltered series — filtered down to `selectedRange` for display.
    let data: [(Date, Double)]
    @Binding var selectedRange: TrendRange
    /// When `true` (default — every existing call site's exact appearance,
    /// e.g. `ExerciseHistoryView.swift:76-78`), wraps the header+chart in its
    /// own `GSCard(bordered: true)` as before. Pass `false` to render just
    /// the header+chart content with no card/border/padding of its own, so a
    /// caller can fold it into ONE surrounding `GSCard` alongside sibling
    /// content — StatsTabView's Body Weight card (`bodyWeightCardView`) does
    /// this to match the single-GSCard-per-card idiom every other Stats-tab
    /// card uses (reviewer Finding 1, Phase H Task 3 fix wave 1). Declared
    /// last with a default so it doesn't disturb the synthesized memberwise
    /// init's existing `title:data:selectedRange:` call shape.
    let embedInCard: Bool = true

    private var filteredData: [(Date, Double)] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: .now) else {
            return data
        }
        return data.filter { $0.0 >= cutoff }
    }

    var body: some View {
        if embedInCard {
            GSCard(bordered: true) {
                chartContent
                    .padding(16)
            }
        } else {
            chartContent
        }
    }

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GSSectionHeader(title)
                Spacer()
                rangePicker
            }
            if filteredData.isEmpty {
                Text("Not enough data yet.")
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            } else {
                Chart(Array(filteredData.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.0), y: .value("Est. 1RM", point.1))
                        .foregroundStyle(theme.accent)
                    PointMark(x: .value("Date", point.0), y: .value("Est. 1RM", point.1))
                        .foregroundStyle(theme.accent)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 140)
            }
        }
    }

    // Canvas: 3-way segmented toggle, top-right of the card.
    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(TrendRange.allCases) { range in
                let isSelected = range == selectedRange
                Button {
                    selectedRange = range
                } label: {
                    Text(range.rawValue)
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .foregroundStyle(isSelected ? theme.bg : theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(isSelected ? theme.accent : Color.clear)
                        .overlay(
                            Rectangle().strokeBorder(theme.neutral400, lineWidth: isSelected ? 0 : 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
