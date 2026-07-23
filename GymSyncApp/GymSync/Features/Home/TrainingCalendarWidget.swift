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
        GSCard(bordered: false) {
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
        }
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

    private struct MonthGroup: Identifiable {
        let id: Date          // month start
        let label: String
        let days: [Date]
    }

    /// v5 (user feedback 2026-07-23): previous / CURRENT / next month — the
    /// current month sits centered, straddled by its neighbors, and renders
    /// its FULL shape (no truncation at today; future days are dimmer, and
    /// days with a scheduled upcoming session are marked in the accent).
    private var monthGroups: [MonthGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)) else { return [] }
        return [-1, 0, 1].compactMap { offset in
            guard let monthStart = cal.date(byAdding: .month, value: offset, to: thisMonthStart) else { return nil }
            let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            let days = (0..<dayCount).compactMap { cal.date(byAdding: .day, value: $0, to: monthStart) }
            return MonthGroup(
                id: monthStart,
                label: monthStart.formatted(.dateTime.month(.abbreviated)),
                days: days
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

    private var monthGroupedField: some View {
        let trained = trainedDays
        let upcoming = upcomingDays
        let today = Calendar.current.startOfDay(for: .now)
        // Fixed 5pt gutters (~1/3 of v4's) with the trio centered as a block —
        // the current month straddled symmetrically by its neighbors.
        return HStack(alignment: .top, spacing: 5) {
            ForEach(monthGroups) { month in
                VStack(alignment: .center, spacing: 10) {
                    Text(month.label)
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                    monthGrid(month, trained: trained, upcoming: upcoming, today: today)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training calendar — last month, this month, next month")
    }

    /// One month as a true mini-calendar: 7 weekday columns × week rows,
    /// day 1 offset to its actual weekday (locale first-weekday respected).
    /// Dot semantics: trained = bright · scheduled upcoming = accent ·
    /// past untrained = neutral400 · future = neutral300 (dimmer) ·
    /// today = accent halo.
    private func monthGrid(_ month: MonthGroup, trained: Set<Date>, upcoming: Set<Date>, today: Date) -> some View {
        let cal = Calendar.current
        // Leading blanks before day 1 (0-6), relative to the locale's week start.
        let offset = month.days.first.map { first in
            (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        } ?? 0
        let cellCount = offset + month.days.count
        let weekRows = Int(ceil(Double(cellCount) / 7.0))
        return VStack(alignment: .leading, spacing: 7.5) {
            ForEach(0..<weekRows, id: \.self) { row in
                HStack(spacing: 4.5) {
                    ForEach(0..<7, id: \.self) { column in
                        let dayIdx = row * 7 + column - offset
                        if dayIdx >= 0 && dayIdx < month.days.count {
                            let day = month.days[dayIdx]
                            dot(for: day, trained: trained, upcoming: upcoming, today: today)
                        } else {
                            Color.clear.frame(width: 6.5, height: 6.5)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dot(for day: Date, trained: Set<Date>, upcoming: Set<Date>, today: Date) -> some View {
        let isTrained = trained.contains(day)
        let isUpcoming = upcoming.contains(day)
        let isFuture = day > today
        let fill: Color = isTrained ? theme.text
            : isUpcoming ? theme.accent
            : isFuture ? theme.neutral300      // future: dimmer
            : theme.neutral400                 // past untrained (300 vanished at 5px)
        let size: CGFloat = (isTrained || isUpcoming) ? 6.5 : 5
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .frame(width: 6.5, height: 6.5)
            // Today: faint accent halo so "now" is findable in the field.
            .overlay(
                day == today
                    ? Circle().strokeBorder(theme.accent.opacity(0.8), lineWidth: 1).frame(width: 10.5, height: 10.5)
                    : nil
            )
    }

    // MARK: Upcoming rows

    private var upcomingList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 1)
            // v3: four rows — the calendar consumes the space freed by the
            // removed stat tiles.
            ForEach(Array(upcomingSessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                NavigationLink {
                    LobbyView(session: session)
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
