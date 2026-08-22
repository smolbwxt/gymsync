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
    /// Field #36: finger-scrub readout - the point nearest the touch,
    /// cleared on lift.
    @State private var scrubbed: (Date, Double)? = nil

    /// Header text for the chart's own title row. Pass `""` to omit the
    /// title entirely (the row then holds just the right-aligned range
    /// picker, no blank leading text) — used by callers that already render
    /// their own card header above this chart, e.g. StatsTabView's Body
    /// Weight card, so the card doesn't stack two headers (fix wave 2).
    /// An empty `GSSectionHeader` is NOT rendered in its place because it's
    /// a `maxWidth: .infinity` leading-aligned Text (GSComponents.swift:
    /// 329-345) — an invisible greedy frame, not a clean no-op.
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
    /// init's existing `title:data:selectedRange:` call shape. Must be `var`:
    /// a `let` with an initial value is omitted from the memberwise init
    /// entirely, which would reject the `embedInCard: false` call site.
    var embedInCard: Bool = true

    /// The chart's own `LineMark`/`PointMark` value label AND its VoiceOver
    /// a11y label (Swift Charts derives the accessibility description from
    /// each mark's `.value(_:_:)` label string — there's no separate a11y
    /// override anywhere in `chartContent` below). Defaulted to
    /// `"Est. 1RM"` — every call site's exact prior appearance (this chart
    /// was estimated-1RM-only before Phase O Task 2) — so
    /// `ExerciseHistoryView`'s existing call (`ExerciseHistoryView.swift:
    /// 76-78`, doesn't pass this parameter at all) keeps rendering and
    /// announcing IDENTICALLY. `StatsTabView.bodyWeightCardView` passes
    /// `"Weight"` explicitly — the a11y bug this fixes: a VoiceOver user on
    /// the Body Weight card was hearing every data point announced as
    /// "Est. 1RM", which is simply wrong for a body-weight series.
    /// Declared last (after `embedInCard`) and as `var` with a default for
    /// the exact same memberwise-init reason documented on `embedInCard`
    /// above — a `let` with an initial value is dropped from the
    /// synthesized memberwise init entirely, which would reject any call
    /// site that tries to pass `valueLabel:`.
    var valueLabel: String = "Est. 1RM"

    private var filteredData: [(Date, Double)] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: .now) else {
            return data
        }
        return data.filter { $0.0 >= cutoff }
    }

    var body: some View {
        if embedInCard {
            // gs3D pass (2026-08-13): the embedded form (ExerciseHistoryView)
            // joins the extruded language its Stats siblings now wear.
            chartContent
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gs3DCard(cornerRadius: GSMetrics.radiusMd)
        } else {
            chartContent
        }
    }

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if !title.isEmpty {
                    GSSectionHeader(title)
                }
                Spacer()
                rangePicker
            }
            if filteredData.isEmpty {
                Text("Not enough data yet.")
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            } else {
                Chart(Array(filteredData.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.0), y: .value(valueLabel, point.1))
                        .foregroundStyle(theme.accent)
                    PointMark(x: .value("Date", point.0), y: .value(valueLabel, point.1))
                        .foregroundStyle(theme.accent)
                    // Field #36: the scrub lollipop - rule + emphasized
                    // point + value chip at the finger's nearest sample.
                    if let scrubbed {
                        RuleMark(x: .value("Date", scrubbed.0))
                            .foregroundStyle(theme.neutral500.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(x: .value("Date", scrubbed.0),
                                  y: .value(valueLabel, scrubbed.1))
                            .foregroundStyle(theme.text)
                            .symbolSize(70)
                            .annotation(position: .top, spacing: 6) {
                                VStack(spacing: 1) {
                                    Text("\(Int(scrubbed.1.rounded()))")
                                        .font(GSFont.bold(13, relativeTo: .caption).monospacedDigit())
                                        .foregroundStyle(theme.text)
                                    Text(scrubbed.0.formatted(date: .abbreviated, time: .omitted))
                                        .font(GSFont.body(10, relativeTo: .caption2))
                                        .foregroundStyle(theme.neutral500)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(theme.divider, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                    }
                }
                // Field #36: real axes - dates below, values on the right.
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(theme.divider)
                        AxisValueLabel(format: selectedRange == .eightWeeks
                            ? .dateTime.month(.abbreviated).day()
                            : .dateTime.month(.abbreviated))
                            .foregroundStyle(theme.neutral500)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(theme.divider)
                        AxisValueLabel()
                            .foregroundStyle(theme.neutral500)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        let plotX = drag.location.x - geo[proxy.plotAreaFrame].origin.x
                                        guard let date: Date = proxy.value(atX: plotX) else { return }
                                        scrubbed = filteredData.min {
                                            abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date))
                                        }
                                    }
                                    .onEnded { _ in scrubbed = nil }
                            )
                    }
                }
                .frame(height: 150)
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
                            RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.neutral400, lineWidth: isSelected ? 0 : 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
