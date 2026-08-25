import SwiftUI

// MARK: - BlockCalendarView
//
// "The block, in time" (owner 2026-08-25: "it's hard to grasp where in
// time we are"). A real three-month grid anchored on the block's own
// start month — current month LEFT, because a block spans weeks and
// reads forward — with the week chips above it and a per-week sheet
// that slides up on tap.
//
// Every mark is read, not assumed (design-spec §1.5). In-block days come
// from the enrollment's start date and week count; filled days are
// sessions actually COMPLETED; accent days are sessions actually
// SCHEDULED. The app does not guess which weekdays you train — it shows
// the ones on your calendar.
struct BlockCalendarView: View {
    let enrollment: ProgramEnrollment?
    let weeks: [ProgramWeek]

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var completedDays: Set<Date> = []
    @State private var scheduledDays: Set<Date> = []
    @State private var selectedWeek = 1
    @State private var sheetWeek: WeekRef?
    @State private var loading = true

    private struct WeekRef: Identifiable { let id: Int }

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if enrollment == nil && !loading {
                    emptyCard
                } else {
                    startsRow
                    weekChips
                    calendarCard
                    seriesCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
        .sheet(item: $sheetWeek) { ref in
            WeekScheduleSheet(weekNumber: ref.id,
                              window: window(for: ref.id),
                              completed: completedDays,
                              scheduled: scheduledDays)
                .presentationDetents([.height(280)])
        }
    }

    // MARK: Rows

    private var startsRow: some View {
        HStack(spacing: 10) {
            Text("STARTS")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Spacer()
            Text(startText)
                .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(theme.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private var weekChips: some View {
        HStack(spacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let number = index + 1
                Button {
                    selectedWeek = number
                    sheetWeek = WeekRef(id: number)
                } label: {
                    Text("W\(number)")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .foregroundStyle(number == selectedWeek ? theme.bg : theme.neutral700)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.gs3D(face: number == selectedWeek ? theme.accent : theme.raised3DFace,
                                   lip: theme.raised3DLip,
                                   cornerRadius: 8, lipHeight: 3))
                .accessibilityLabel("Week \(number)\(week.isDeload ? ", deload" : ""), edit its schedule")
            }
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE BLOCK, IN TIME")
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .tracking(0.3)
                    .foregroundStyle(theme.text)
                Spacer()
                if let last = blockEnd {
                    Text("ENDS \(short(last).uppercased())")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(blockGold)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(months, id: \.self) { month in
                    monthColumn(month)
                }
            }
            legend
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private func monthColumn(_ month: Date) -> some View {
        VStack(spacing: 5) {
            Text(monthLabel(month).uppercased())
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral700)
            HStack(spacing: 2) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(GSFont.bold(7, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(monthRows(month).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            RoundedRectangle(cornerRadius: 2)
                .fill(fill(for: day))
                .frame(height: 10)
                .frame(maxWidth: .infinity)
                .overlay {
                    if calendar.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(theme.accent, lineWidth: 1.5)
                    }
                }
        } else {
            Color.clear.frame(height: 10).frame(maxWidth: .infinity)
        }
    }

    private func fill(for day: Date) -> Color {
        let key = calendar.startOfDay(for: day)
        if let last = blockEnd, calendar.isDate(key, inSameDayAs: last) { return blockGold }
        if completedDays.contains(key) { return theme.text }
        if scheduledDays.contains(key) { return theme.accent }
        if inSelectedWeek(key) { return theme.accent.opacity(0.22) }
        if inBlock(key) { return theme.neutral500.opacity(0.35) }
        return theme.neutral500.opacity(0.12)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(theme.text, "DONE")
            legendDot(theme.accent, "BOOKED")
            legendDot(blockGold, "BLOCK ENDS")
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 8)
            Text(label)
                .font(GSFont.bold(8, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral700)
        }
    }

    private var seriesCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("THE SERIES")
                .font(GSFont.bold(20, relativeTo: .title3))
                .tracking(0.3)
                .foregroundStyle(theme.text)
            if let enrollment, let template = enrollment.template {
                Text(template.name.hasPrefix("Coach · ")
                     ? String(template.name.dropFirst("Coach · ".count))
                     : template.name)
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text(spanText)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
            }
            NavigationLink {
                CoachWizardView(onCreated: {})
                    .background(theme.bg)
                    .navigationTitle("Plan the next block")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Text("PLAN THE NEXT BLOCK")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.5)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO BLOCK ON THE BAR")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("A forged block lands on this calendar with its weeks and its finish line.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    // MARK: Dates

    private var startDate: Date? { enrollment.map { calendar.startOfDay(for: $0.startedOn) } }

    private var blockEnd: Date? {
        guard let startDate, !weeks.isEmpty else { return nil }
        return calendar.date(byAdding: .day, value: weeks.count * 7 - 1, to: startDate)
    }

    private var startText: String {
        guard let startDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · MMM d"
        return formatter.string(from: startDate).uppercased()
    }

    private var spanText: String {
        guard let startDate, let blockEnd else { return "" }
        return "\(short(startDate).uppercased()) – \(short(blockEnd).uppercased())"
    }

    private func short(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    /// Three months from the block's start month — current month LEFT
    /// (owner 2026-08-25), because a block reads forward in time.
    private var months: [Date] {
        guard let startDate else { return [] }
        let comps = calendar.dateComponents([.year, .month], from: startDate)
        guard let first = calendar.date(from: comps) else { return [] }
        return (0..<3).compactMap { calendar.date(byAdding: .month, value: $0, to: first) }
    }

    /// Monday-first rows of a month, nil-padded at both ends.
    private func monthRows(_ month: Date) -> [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        // Calendar.weekday is 1=Sunday; shift so Monday is 0.
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func window(for week: Int) -> (start: Date, end: Date) {
        guard let enrollment else { return (Date(), Date()) }
        return ProgramMath.weekWindow(startedOn: enrollment.startedOn, week: week)
    }

    private func inBlock(_ day: Date) -> Bool {
        guard let startDate, let blockEnd else { return false }
        return day >= startDate && day <= blockEnd
    }

    private func inSelectedWeek(_ day: Date) -> Bool {
        guard enrollment != nil else { return false }
        let w = window(for: selectedWeek)
        return day >= calendar.startOfDay(for: w.start) && day < w.end
    }

    // MARK: Load

    private func load() async {
        guard loading else { return }
        defer { loading = false }
        if let enrollment, !weeks.isEmpty {
            selectedWeek = ProgramMath.currentWeek(startedOn: enrollment.startedOn,
                                                   weeks: weeks.count)
        }
        guard let userID = appState.currentProfile?.id else { return }
        if let history = try? await SessionRepository.history(userID: userID, limit: 120) {
            completedDays = Set(history.compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) })
        }
        if let upcoming = try? await SessionRepository.upcoming() {
            scheduledDays = Set(upcoming.compactMap { $0.scheduledFor }
                .map { calendar.startOfDay(for: $0) })
        }
    }
}

// MARK: - WeekScheduleSheet
//
// The blocking line that slides up when a week chip is tapped. It shows
// that week's REAL days — what is booked, what is done — because a
// per-week distinct schedule has no storage model yet (SessionSeries
// carries one recurring pattern for the whole block, not one per week).
// Rather than fake an editor that cannot persist, this states the week
// honestly and hands off to the scheduler that does persist.
struct WeekScheduleSheet: View {
    let weekNumber: Int
    let window: (start: Date, end: Date)
    let completed: Set<Date>
    let scheduled: Set<Date>

    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showScheduler = false

    private var calendar: Calendar { .current }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: window.start)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEK \(weekNumber)")
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .tracking(0.3)
                    .foregroundStyle(theme.text)
                Spacer()
                Text(rangeText.uppercased())
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
            }
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 4) {
                        Text(letter(day))
                            .font(GSFont.bold(9, relativeTo: .caption2))
                            .foregroundStyle(theme.neutral500)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(fill(day))
                            .frame(height: 34)
                            .overlay {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(GSFont.bold(11, relativeTo: .caption))
                                    .foregroundStyle(ink(day))
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Button {
                showScheduler = true
            } label: {
                Text("SCHEDULE A SESSION")
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .tracking(0.5)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.gs3D(face: theme.accent, lip: theme.raised3DLip,
                               cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .sheet(isPresented: $showScheduler) {
            ScheduleSessionView { _ in
                showScheduler = false
                dismiss()
            }
        }
    }

    private var rangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let last = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: window.start))
            ?? window.start
        return "\(formatter.string(from: window.start)) – \(formatter.string(from: last))"
    }

    private func letter(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: day).uppercased()
    }

    private func fill(_ day: Date) -> Color {
        let key = calendar.startOfDay(for: day)
        if completed.contains(key) { return theme.text }
        if scheduled.contains(key) { return theme.accent }
        return theme.surface
    }

    private func ink(_ day: Date) -> Color {
        let key = calendar.startOfDay(for: day)
        return (completed.contains(key) || scheduled.contains(key)) ? theme.bg : theme.neutral500
    }
}
