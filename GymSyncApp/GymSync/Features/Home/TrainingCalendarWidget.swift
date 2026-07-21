import SwiftUI

/// Home's training-calendar widget (redesign, all-tabs proof: the "Upcoming
/// Sessions" list becomes a calendar). Three stacked parts inside one Onyx
/// widget card:
///   1. **Dot-grid texture** — the last 12 weeks of training, one cell per
///      day (GitHub-graph orientation: columns = weeks, rows = weekdays).
///      Filled = a completed session that day, tinted **accent** for solo
///      days and the **group identity color** (`GSGroupColor`, stable
///      Okabe-Ito) when that day's session was a group session. Per spec §4
///      the grid is TEXTURE — how busy training is — never the precise
///      "which crew" record; that lives in the rows below with real labels.
///   2. **Legend** — Solo (accent) + each group with its identity color.
///   3. **Upcoming rows** — up to 3 upcoming sessions, each a NavigationLink
///      to `LobbyView`: group-colored avatar tile (initials; "You" on the
///      accent for solo), title, group/state subtitle, right-aligned when.
///
/// Empty state (spec §6, null-states proof): no history AND no upcoming →
/// a card-anchored invite ("Your training calendar") with Find-a-crew +
/// Schedule actions — never a centered float.
struct TrainingCalendarWidget: View {
    @Environment(\.gsTheme) private var theme

    let completedSessions: [WorkoutSession]
    let upcomingSessions: [WorkoutSession]
    let groups: [GymGroup]
    /// Resolves a session's display title (HomeView's `routineLabel(for:)`).
    let titleFor: (WorkoutSession) -> String
    let onSchedule: () -> Void
    let onFindCrew: () -> Void

    private static let weeks = 12

    var body: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isEmpty {
                    emptyBody
                } else {
                    dotGrid.padding(.top, 14)
                    legend.padding(.top, 12)
                    if !upcomingSessions.isEmpty {
                        upcomingList.padding(.top, 14)
                    }
                }
            }
            .padding(16)
        }
    }

    private var isEmpty: Bool { completedSessions.isEmpty && upcomingSessions.isEmpty }

    // MARK: Header — kicker + "+ Schedule" (absorbs the old standalone button)

    private var header: some View {
        HStack {
            GSSectionHeader("Training calendar")
            Button(action: onSchedule) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Schedule")
                        .font(GSFont.bold(12, relativeTo: .caption))
                }
                .foregroundStyle(theme.accent)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Schedule session")
        }
    }

    // MARK: Dot grid (texture)

    /// Day → fill for the last `weeks`×7 days. Group sessions win the tint for
    /// the day (their color IS the day's story); multiple sessions collapse to
    /// the first — texture, not a record.
    private var dayFills: [Date: Color] {
        let cal = Calendar.current
        var fills: [Date: Color] = [:]
        for session in completedSessions {
            guard let when = session.completedAt ?? session.startedAt ?? session.scheduledFor else { continue }
            let day = cal.startOfDay(for: when)
            if let groupID = session.groupID {
                fills[day] = GSGroupColor.color(for: groupID)
            } else if fills[day] == nil {
                fills[day] = theme.accent
            }
        }
        return fills
    }

    private var gridDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let count = Self.weeks * 7
        return (0..<count).compactMap { cal.date(byAdding: .day, value: -(count - 1 - $0), to: today) }
    }

    private var dotGrid: some View {
        let fills = dayFills
        let days = gridDays
        // Columns = weeks (oldest → newest), rows = weekday.
        return HStack(alignment: .top, spacing: 4) {
            ForEach(0..<Self.weeks, id: \.self) { week in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { day in
                        let idx = week * 7 + day
                        if idx < days.count {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(fills[days[idx]] ?? theme.neutral300)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training activity, last \(Self.weeks) weeks")
    }

    // MARK: Legend

    private var legend: some View {
        // Only groups that actually appear (member groups), capped for space.
        let shown = groups.prefix(3)
        return HStack(spacing: 14) {
            legendChip(color: theme.accent, label: "Solo")
            ForEach(Array(shown)) { group in
                legendChip(color: GSGroupColor.color(for: group.id), label: group.name)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
        }
    }

    // MARK: Upcoming rows

    private var upcomingList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 1)
            ForEach(Array(upcomingSessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                NavigationLink {
                    LobbyView(session: session)
                } label: {
                    upcomingRow(session)
                }
                .buttonStyle(.plain)
                if index < min(upcomingSessions.count, 3) - 1 {
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
