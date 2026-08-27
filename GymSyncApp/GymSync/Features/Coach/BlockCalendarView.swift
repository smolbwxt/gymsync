import SwiftUI

// MARK: - BlockCalendarView
//
// "The block, in time" (owner 2026-08-25: "it's hard to grasp where in
// time we are"). A real month grid anchored on the block's own start
// month — current month LEFT, because a block spans weeks and reads
// forward — with the week chips above it and a per-week sheet that
// slides up on tap.
//
// The grid spans exactly the months the block TOUCHES (owner 2026-08-25:
// "blocks can be anywhere from 2 weeks to a few months, so lets not
// constrict ourselves"). A fortnight shows one month; a sixteen-week
// block shows four or five and wraps. Months lay out three to a row and
// short rows are padded, so a day cell is the same size whatever the
// block's length — the calendar never rescales itself under you.
//
// Every mark is read, not assumed (design-spec §1.5). In-block days come
// from the enrollment's start date and week count; filled days are
// sessions actually COMPLETED; accent days are sessions actually
// SCHEDULED. The app does not guess which weekdays you train — it shows
// the ones on your calendar.
struct BlockCalendarView: View {
    let enrollment: ProgramEnrollment?
    let weeks: [ProgramWeek]
    /// Owner 2026-08-27: "the top of this page should be the content
    /// from the on the calendar page." Embedded, this view renders the
    /// block-in-time card inside the program page's own scroll - no
    /// scroll of its own, no week chips (the program page has the week
    /// buttons), no series card (the ledger owns the next build).
    var embedded = false
    /// The program page's selected week, so the grid tints the same week
    /// the buttons show.
    var highlightedWeek: Int? = nil
    /// Bumped by the host when it books a week; the grid re-reads so a
    /// session booked from the program page shows up here immediately.
    var refreshToken = 0
    /// Told when THIS view's own sheet changes a schedule, so the host
    /// can refresh its week buttons.
    var onScheduleChanged: (() async -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var completedDays: Set<Date> = []
    @State private var scheduledDays: Set<Date> = []
    /// Per-week overrides (owner 2026-08-25). A week absent from this map
    /// simply inherits the block's default rhythm.
    @State private var weekSchedules: [Int: BlockWeekSchedule] = [:]
    /// Cached because `fill(for:)` runs once per calendar cell — a
    /// computed property here would rebuild the whole set ~90 times per
    /// render.
    @State private var plannedDays: Set<Date> = []
    @State private var selectedWeek = 1
    @State private var sheetWeek: WeekRef?
    /// A block was just built from this calendar; push a FRESH schedule
    /// page. This view's own `enrollment`/`weeks` are `let` values
    /// captured before the build, so it cannot render the new block -
    /// but a fresh ProgramScheduleView fetches, so the athlete lands on
    /// what they just made instead of popping back to a calendar drawing
    /// the block they replaced.
    @State private var freshScheduleAfterBuild = false
    @State private var loading = true

    private struct WeekRef: Identifiable { let id: Int }

    private var calendar: Calendar { .current }

    /// The design system's `--onyx-gold` (goals, streaks, finish lines).
    /// Not a GSTheme token — semantic colors outside the ramp follow the
    /// HomeView precedent of a local `Color.gsHex` constant.
    private let blockGold = Color.gsHex(0xE8C33A)

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 12) {
                    startsRow
                    calendarCard
                }
                .onChange(of: refreshToken) { _, _ in
                    Task { await reloadAll() }
                }
                .onChange(of: highlightedWeek) { _, week in
                    if let week { selectedWeek = week }
                }
            } else {
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
                .navigationDestination(isPresented: $freshScheduleAfterBuild) {
                    ProgramScheduleView()
                        .background(theme.bg)
                }
            }
        }
        .task { await load() }
        .sheet(item: $sheetWeek) { ref in
            WeekScheduleSheet(weekNumber: ref.id,
                              window: window(for: ref.id),
                              enrollmentID: enrollment?.id,
                              existing: weekSchedules[ref.id],
                              completed: completedDays,
                              scheduled: scheduledDays,
                              totalWeeks: weeks.count,
                              startedOn: enrollment?.startedOn,
                              onChanged: { await reloadSchedules() })
                .presentationDetents([.height(500)])
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
                .accessibilityLabel("Week \(number)\(week.isDeload ? ", deload" : "")\(weekSchedules[number] != nil ? ", custom schedule" : ""), edit its schedule")
                .overlay(alignment: .topTrailing) {
                    if weekSchedules[number] != nil {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 5, height: 5)
                            .padding(3)
                    }
                }
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
            VStack(spacing: 12) {
                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(row, id: \.self) { month in
                            monthColumn(month)
                        }
                        // Pad the final row so months keep a constant width.
                        ForEach(Array(0..<(3 - row.count)), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
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
        if plannedDays.contains(key) { return theme.accent.opacity(0.55) }
        if inSelectedWeek(key) { return theme.accent.opacity(0.22) }
        if inBlock(key) { return theme.neutral500.opacity(0.35) }
        return theme.neutral500.opacity(0.12)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(theme.text, "DONE")
            legendDot(theme.accent, "BOOKED")
            legendDot(theme.accent.opacity(0.55), "PLANNED")
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
                // .handled: the calendar answers the build by pushing a
                // FRESH ProgramScheduleView (state above). Its own
                // captured enrollment/weeks stay stale - acceptable one
                // level back - but the athlete's next screen is the block
                // they just built, not the one they replaced.
                ConsultEntryView(onBuilt: { freshScheduleAfterBuild = true })
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

    /// Every month the block touches, start month first — current month
    /// LEFT (owner 2026-08-25), because a block reads forward in time.
    /// A 2-week block yields one month; a 5-month block yields five.
    private var months: [Date] {
        guard let startDate, let end = blockEnd else { return [] }
        guard let first = firstOfMonth(startDate), let last = firstOfMonth(end) else { return [] }
        var out: [Date] = []
        var cursor = first
        // The 24 cap is a runaway guard, not a product limit: a block
        // longer than two years is a data error, not a training plan.
        while cursor <= last, out.count < 24 {
            out.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private func firstOfMonth(_ date: Date) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    /// Months three to a row. Rows are padded to three so a day cell keeps
    /// the same width whether the block spans one month or six.
    private var monthGrid: [[Date]] {
        stride(from: 0, to: months.count, by: 3).map {
            Array(months[$0..<min($0 + 3, months.count)])
        }
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
        await reloadAll()
    }

    /// Every read, re-runnable: the embedded copy on the program page
    /// re-reads when that page books a week.
    private func reloadAll() async {
        if let enrollment, !weeks.isEmpty {
            selectedWeek = highlightedWeek
                ?? ProgramMath.currentWeek(startedOn: enrollment.startedOn,
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
        await reloadSchedules()
    }

    private func reloadSchedules() async {
        guard let enrollment else { return }
        weekSchedules = await BlockWeekScheduleRepository.forEnrollment(enrollment.id)
        plannedDays = computePlannedDays()
        await onScheduleChanged?()
    }

    /// Days a per-week override PLANS — distinct from days with a real
    /// session on them. Planned is intent; booked is a session row.
    private func computePlannedDays() -> Set<Date> {
        guard enrollment != nil else { return [] }
        var days: Set<Date> = []
        for (weekNumber, schedule) in weekSchedules where !schedule.weekdays.isEmpty {
            let start = calendar.startOfDay(for: window(for: weekNumber).start)
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                if schedule.weekdays.contains(calendar.component(.weekday, from: day)) {
                    days.insert(day)
                }
            }
        }
        return days
    }
}

// MARK: - WeekScheduleSheet
//
// The blocking line that slides up when a week chip is tapped, and — as
// of the block_week_schedules table — a REAL editor. Toggling days
// upserts that week's override; "same as the block" deletes it so the
// week falls back to the block's default rhythm rather than storing an
// empty day list, which would mean "rest all week" instead of "no
// opinion".
//
// Weekday values are Calendar's own (1 = Sunday ... 7 = Saturday); the
// chips merely DISPLAY Monday-first.
struct WeekScheduleSheet: View {
    let weekNumber: Int
    let window: (start: Date, end: Date)
    let enrollmentID: UUID?
    let existing: BlockWeekSchedule?
    let completed: Set<Date>
    let scheduled: Set<Date>
    /// The block's length and start, so APPLY TO ALL WEEKS can address
    /// every week's window. Optional: a host without a block still gets
    /// the single-week sheet.
    var totalWeeks: Int? = nil
    var startedOn: Date? = nil
    let onChanged: () async -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDays: Set<Int> = []
    @State private var time = Date()
    @State private var saving = false
    @State private var loaded = false
    /// Owner 2026-08-27: "an option to apply to all weeks".
    @State private var applyToAll = false
    /// The block's day routines, Monday-first across the chosen days, so
    /// each booked session opens on the right prescription.
    @State private var routines: [Routine] = []

    private var calendar: Calendar { .current }
    /// Display order, Monday-first, in Calendar weekday values.
    private let displayOrder = [2, 3, 4, 5, 6, 7, 1]
    private let letters = ["", "S", "M", "T", "W", "T", "F", "S"]

    private var days: [Date] {
        (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0,
                          to: calendar.startOfDay(for: window.start))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            dayToggles
            timeRow
            if let totalWeeks, totalWeeks > 1 {
                applyToAllRow(totalWeeks)
            }
            actions
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .task {
            guard !loaded else { return }
            loaded = true
            selectedDays = Set(existing?.weekdays ?? [])
            var components = DateComponents()
            components.hour = existing?.hour ?? 18
            components.minute = existing?.minute ?? 0
            time = calendar.date(from: components) ?? Date()
            // The block's routines, in the order the generator wrote them.
            if let ownerID = appState.currentProfile?.id,
               let all = try? await RoutineRepository.fetchAll(ownerID: ownerID) {
                routines = all
                    .filter { $0.name.hasPrefix("Coach · ") && $0.prescribedBy == nil }
                    .sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
            }
        }
    }

    private func applyToAllRow(_ total: Int) -> some View {
        Button {
            applyToAll.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: applyToAll ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(applyToAll ? theme.accent : theme.neutral500)
                VStack(alignment: .leading, spacing: 2) {
                    Text("APPLY TO ALL \(total) WEEKS")
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .tracking(0.8)
                        .foregroundStyle(theme.text)
                    Text("Same days, same time, every week of the block.")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
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
    }

    private var dayToggles: some View {
        HStack(spacing: 6) {
            ForEach(displayOrder, id: \.self) { weekday in
                Button {
                    if selectedDays.contains(weekday) { selectedDays.remove(weekday) }
                    else { selectedDays.insert(weekday) }
                } label: {
                    VStack(spacing: 3) {
                        Text(letters[weekday])
                            .font(GSFont.bold(11, relativeTo: .caption))
                            .foregroundStyle(selectedDays.contains(weekday) ? theme.bg : theme.neutral700)
                        if let day = date(for: weekday) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(GSFont.bold(9, relativeTo: .caption2).monospacedDigit())
                                .foregroundStyle(selectedDays.contains(weekday) ? theme.bg.opacity(0.8) : theme.neutral500)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.gs3D(face: selectedDays.contains(weekday) ? theme.accent : theme.raised3DFace,
                                   lip: theme.raised3DLip,
                                   cornerRadius: 8, lipHeight: 3))
                .overlay(alignment: .bottom) {
                    // A day that already carries a real session is marked,
                    // so toggling never hides what is actually booked.
                    if let day = date(for: weekday), marked(day) {
                        Circle()
                            .fill(completed.contains(calendar.startOfDay(for: day)) ? theme.text : theme.accent)
                            .frame(width: 4, height: 4)
                            .padding(.bottom, 6)
                    }
                }
                .accessibilityLabel(label(for: weekday))
            }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 10) {
            Text("AT")
                .font(GSFont.bold(12, relativeTo: .caption))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
            Spacer()
        }
    }

    private var actions: some View {
        VStack(spacing: 9) {
            Button {
                save()
            } label: {
                Text(saving ? "BOOKING..."
                     : applyToAll ? "SET ALL \(totalWeeks ?? 1) WEEKS" : "SET WEEK \(weekNumber)")
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .tracking(0.5)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.gs3D(face: theme.accent, lip: theme.raised3DLip,
                               cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
            .disabled(saving || enrollmentID == nil)

            if existing != nil {
                Button {
                    clear()
                } label: {
                    Text("SAME AS THE BLOCK")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                .disabled(saving)
            }
        }
    }

    /// Record the intent AND book the sessions (owner 2026-08-27: "Book
    /// real sessions"). One week, or every week of the block.
    private func save() {
        guard let enrollmentID, !saving else { return }
        saving = true
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 18
        let minute = components.minute ?? 0
        let targets: [Int] = applyToAll && (totalWeeks ?? 1) > 1
            ? Array(1...(totalWeeks ?? 1)) : [weekNumber]
        Task {
            defer { saving = false }
            for week in targets {
                await BlockWeekScheduleRepository.save(
                    enrollmentID: enrollmentID, weekNumber: week,
                    weekdays: Array(selectedDays), hour: hour, minute: minute)
                let target: (start: Date, end: Date)
                if week == weekNumber {
                    target = window
                } else if let startedOn {
                    target = ProgramMath.weekWindow(startedOn: startedOn, week: week)
                } else {
                    continue
                }
                await WeekBooker.book(window: target, weekdays: selectedDays,
                                      hour: hour, minute: minute,
                                      routines: routines)
            }
            await onChanged()
            dismiss()
        }
    }

    /// Drop the override AND the sessions it booked - a cleared week is
    /// an empty week, not a week with ghost sessions on it.
    private func clear() {
        guard let enrollmentID, !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            await BlockWeekScheduleRepository.clear(enrollmentID: enrollmentID,
                                                    weekNumber: weekNumber)
            await WeekBooker.book(window: window, weekdays: [], hour: 18, minute: 0,
                                  routines: [])
            await onChanged()
            dismiss()
        }
    }

    private func date(for weekday: Int) -> Date? {
        days.first { calendar.component(.weekday, from: $0) == weekday }
    }

    private func marked(_ day: Date) -> Bool {
        let key = calendar.startOfDay(for: day)
        return completed.contains(key) || scheduled.contains(key)
    }

    private func label(for weekday: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday",
                     "Thursday", "Friday", "Saturday"]
        let name = names.indices.contains(weekday) ? names[weekday] : ""
        return selectedDays.contains(weekday) ? "\(name), training day" : name
    }

    private var rangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let last = calendar.date(byAdding: .day, value: 6,
                                 to: calendar.startOfDay(for: window.start)) ?? window.start
        return "\(formatter.string(from: window.start)) - \(formatter.string(from: last))"
    }
}
