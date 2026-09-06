import SwiftUI

/// Home's training-calendar widget, v2 — rebuilt to the reference screenshot's
/// calendar (Inspo/f80af551…jpg): an **airy monochrome dot field** under month
/// labels — small dim round dots for the last ~10 weeks, **bright near-white
/// dots** on days you trained. Deliberately monochrome and legend-free: the
/// v1 GitHub-style tight grid with per-group colors read as noise at 6px
/// (user feedback 2026-07-21); precise "which crew" attribution lives in the
/// upcoming rows below with their group-colored avatars, not in the texture.
///
/// Parts:
///   1. Header — "TRAINING CALENDAR" kicker + "+ Schedule" action (kept).
///   2. Month labels + dot field (column-major chronological, 4 dots per
///      column, oldest top-left → today bottom-right, matching the ref).
///   3. Upcoming rows (kept) — up to 3, NavigationLink → LobbyView, group
///      avatar tiles in identity colors.
///
/// Empty state (spec §6): card-anchored invite, never a centered float.
struct TrainingCalendarWidget: View {
    @Environment(\.gsTheme) private var theme

    let completedSessions: [WorkoutSession]
    let upcomingSessions: [WorkoutSession]
    let groups: [GymGroup]
    /// Resolves a session's display title (HomeView's `routineLabel(for:)`).
    let titleFor: (WorkoutSession) -> String
    let onSchedule: () -> Void
    let onFindCrew: () -> Void

    var body: some View {
        // 3D pass (2026-08): static extruded card (`.gs3DCard`) replaces the
        // flat GSCard — this container is large and not itself tappable (the
        // upcoming rows inside keep their own NavigationLinks), so it sits
        // still on its lip. The dot field reads against the raised face:
        // trained (text) and upcoming (accent) dots keep their contrast in
        // every palette; the dim past/future dots stay dim.
        VStack(alignment: .leading, spacing: 0) {
            header
            if isEmpty {
                emptyBody
            } else {
                monthGroupedField.padding(.top, 14)
                if !upcomingSessions.isEmpty {
                    upcomingList.padding(.top, 18)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    private var isEmpty: Bool { completedSessions.isEmpty && upcomingSessions.isEmpty }

    // MARK: Header — kicker + upcoming count
    // (v3, declutter round: the "+ Schedule" action moved out to Home's own
    // schedule widget; the header's right side is the upcoming count again.)

    private var header: some View {
        HStack {
            GSSectionHeader("Training calendar")
            if !upcomingSessions.isEmpty {
                Text("\(upcomingSessions.count) UPCOMING")
                    .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral500)
            }
        }
    }

    // MARK: Month-grouped dot field (v4 — true calendar shape)
    //
    // v3 grouped the months but filled them column-major (abstract texture).
    // User follow-up: months should have the NORMAL shape of a calendar —
    // so each cluster is now a true mini-calendar: 7 weekday columns
    // (respecting Calendar.current.firstWeekday), weeks as rows, day 1
    // offset to its actual weekday. Besides familiarity, this makes the
    // texture meaningful: training every Monday reads as a vertical bright
    // line. Current month's dots stop at today (today haloed).

    /// The trained-day set, day-granular.
    private var trainedDays: Set<Date> {
        let cal = Calendar.current
        var days: Set<Date> = []
        for session in completedSessions {
            guard let when = session.completedAt ?? session.startedAt ?? session.scheduledFor else { continue }
            days.insert(cal.startOfDay(for: when))
        }
        return days
    }

    /// v5 (user feedback 2026-07-23): previous / CURRENT / next month — the
    /// current month sits centered, straddled by its neighbors, and renders
    /// its FULL shape (no truncation at today; future days are dimmer, and
    /// days with a scheduled upcoming session are marked in the accent).
    ///
    /// v7 (task D1): this is now a PROJECTION onto `TrainingMonthField.Month`
    /// rather than a field of its own — the widget keeps the `Calendar` truth
    /// (which day is today, which real dates were trained) and hands the
    /// shared field the integers it draws with. Every rule the old private
    /// field applied survives the projection unchanged:
    ///   * `position` reproduces `day > today`: last month is entirely past,
    ///     next month entirely future, and the current month splits on its
    ///     own `today` day number;
    ///   * `today` is set on the current month only, which is the only month
    ///     whose dates could ever have equalled `today` before;
    ///   * `trained`/`planned` are the same `Set<Date>` membership tests, run
    ///     against the same generated day dates, recorded as day numbers.
    private var fieldMonths: [TrainingMonthField.Month] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let trained = trainedDays
        let upcoming = upcomingDays
        guard let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)) else { return [] }
        return [-1, 0, 1].compactMap { offset in
            guard let monthStart = cal.date(byAdding: .month, value: offset, to: thisMonthStart) else { return nil }
            let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            let days = (0..<dayCount).compactMap { cal.date(byAdding: .day, value: $0, to: monthStart) }
            var trainedDayNumbers: Set<Int> = []
            var plannedDayNumbers: Set<Int> = []
            for day in days {
                let number = cal.component(.day, from: day)
                if trained.contains(day) { trainedDayNumbers.insert(number) }
                if upcoming.contains(day) { plannedDayNumbers.insert(number) }
            }
            let position: TrainingMonthField.Month.Position =
                offset < 0 ? .past : (offset == 0 ? .current : .future)
            return TrainingMonthField.Month(
                id: "\(cal.component(.year, from: monthStart))-\(cal.component(.month, from: monthStart))",
                label: monthStart.formatted(.dateTime.month(.abbreviated)),
                dayCount: dayCount,
                leadingBlanks: days.first.map { first in
                    (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
                } ?? 0,
                trained: trainedDayNumbers,
                planned: plannedDayNumbers,
                today: offset == 0 ? cal.component(.day, from: today) : nil,
                position: position
            )
        }
    }

    /// Days with a scheduled upcoming session — accent marks in the field.
    private var upcomingDays: Set<Date> {
        let cal = Calendar.current
        var days: Set<Date> = []
        for session in upcomingSessions {
            guard let when = session.scheduledFor else { continue }
            days.insert(cal.startOfDay(for: when))
        }
        return days
    }

    /// Measured field width — drives dot sizing so the three month grids FILL
    /// the card (v6, on-device feedback: fixed-size dots centered in
    /// equal-flex thirds left large dead gaps). Seeded to a typical width;
    /// `onGeometryChange` corrects it on first layout.
    @State private var fieldWidth: CGFloat = 326

    /// The shared field (task D1), fed this widget's measured width.
    ///
    /// The geometry observation stays HERE and rides on the outside of the
    /// field rather than moving into it: the field is what gets measured
    /// either way (`.frame(maxWidth: .infinity)` is applied inside it, and
    /// the accessibility modifiers between do not affect layout), so the
    /// width this reads is the same width the old private field read — and
    /// `TrainingMonthField` stays free of state, which is what lets the
    /// catalog's callers render it hermetically at the default 326.
    private var monthGroupedField: some View {
        TrainingMonthField(months: fieldMonths, fieldWidth: fieldWidth)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if width > 0 { fieldWidth = width }
            }
    }

    // MARK: Upcoming rows

    private var upcomingList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 1)
            // v3: four rows — the calendar consumes the space freed by the
            // removed stat tiles.
            ForEach(Array(upcomingSessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                NavigationLink {
                    // .id — session-identity pin (HomeView's navigateToJoined
                    // destination comment has the full field-bug story).
                    LobbyView(session: session)
                        .id(session.id)
                } label: {
                    upcomingRow(session)
                }
                .buttonStyle(.plain)
                if index < min(upcomingSessions.count, 4) - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
    }

    private func upcomingRow(_ session: WorkoutSession) -> some View {
        let group = session.groupID.flatMap { gid in groups.first(where: { $0.id == gid }) }
        return HStack(spacing: 11) {
            avatarTile(session: session, group: group)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(titleFor(session))
                        .font(GSFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if session.seriesID != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                }
                Text(group?.name ?? "Solo")
                    .font(GSFont.body(11.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(whenText(session))
                .font(GSFont.bodyMedium(10.5, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func avatarTile(session: WorkoutSession, group: GymGroup?) -> some View {
        let fill: Color = group.map { GSGroupColor.color(for: $0.id) } ?? theme.accent
        let label = group.map { initials($0.name) } ?? "You"
        let ink: Color = group.map { GSGroupColor.onColor(for: $0.id) } ?? theme.bg
        return RoundedRectangle(cornerRadius: 9)
            .fill(fill)
            .frame(width: 30, height: 30)
            .overlay(
                Text(label)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .foregroundStyle(ink)
            )
    }

    private func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private func whenText(_ session: WorkoutSession) -> String {
        if let when = session.scheduledFor {
            return when.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                + "\n" + when.formatted(.dateTime.hour().minute())
        }
        return session.state.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: Empty state (card-anchored, spec §6)

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.neutral300)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "calendar")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(theme.accent)
                )
                .padding(.top, 14)
            Text("Your training calendar")
                .font(GSFont.bold(16, relativeTo: .headline))
                .foregroundStyle(theme.text)
                .padding(.top, 11)
            Text("Schedule a session or join a crew — upcoming lifts and your training history show up here.")
                .font(GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 9) {
                Button("Find a crew", action: onFindCrew)
                    .buttonStyle(GSPrimaryButtonStyle(fontSize: 13, verticalPadding: 11))
                    .fixedSize()
                Button("Schedule", action: onSchedule)
                    .buttonStyle(GSSecondaryButtonStyle(fontSize: 13, horizontalPadding: 15, verticalPadding: 11))
                    .fixedSize()
            }
            .padding(.top, 14)
        }
    }
}
