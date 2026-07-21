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

    /// Ref grid: 18 columns × 4 rows = 72 days (~10 weeks).
    private static let columns = 18
    private static let rows = 4

    var body: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isEmpty {
                    emptyBody
                } else {
                    monthLabels.padding(.top, 14)
                    dotField.padding(.top, 10)
                    if !upcomingSessions.isEmpty {
                        upcomingList.padding(.top, 16)
                    }
                }
            }
            .padding(16)
        }
    }

    private var isEmpty: Bool { completedSessions.isEmpty && upcomingSessions.isEmpty }

    // MARK: Header — kicker + "+ Schedule"

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

    // MARK: Month labels + dot field (reference style)

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

    /// Last `columns × rows` days, oldest first.
    private var gridDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let count = Self.columns * Self.rows
        return (0..<count).compactMap { cal.date(byAdding: .day, value: -(count - 1 - $0), to: today) }
    }

    /// Month names spanning the grid, evenly spread like the reference
    /// (Jan / Feb / Mar). Derived from the actual day range so the labels
    /// are always truthful.
    private var monthLabels: some View {
        let days = gridDays
        let cal = Calendar.current
        var names: [String] = []
        for day in days {
            let name = day.formatted(.dateTime.month(.abbreviated))
            if names.last != name { names.append(name) }
        }
        _ = cal
        return HStack {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                if index < names.count - 1 { Spacer() }
            }
        }
        .padding(.horizontal, 2)
    }

    /// The airy dot field: column-major chronological (each column is 4
    /// consecutive days, columns run oldest → newest), round 6pt dots, dim
    /// neutral for untrained days, bright near-white for trained days —
    /// monochrome, per the reference.
    private var dotField: some View {
        let days = gridDays
        let trained = trainedDays
        let today = Calendar.current.startOfDay(for: .now)
        return HStack(spacing: 0) {
            ForEach(0..<Self.columns, id: \.self) { column in
                VStack(spacing: 10) {
                    ForEach(0..<Self.rows, id: \.self) { row in
                        let idx = column * Self.rows + row
                        if idx < days.count {
                            let day = days[idx]
                            let isTrained = trained.contains(day)
                            Circle()
                                .fill(isTrained ? theme.text : theme.neutral300)
                                .frame(width: isTrained ? 7 : 5.5, height: isTrained ? 7 : 5.5)
                                .frame(width: 7, height: 7)
                                // Today gets a faint accent halo so "now" is
                                // findable without breaking the mono field.
                                .overlay(
                                    day == today
                                        ? Circle().strokeBorder(theme.accent.opacity(0.8), lineWidth: 1).frame(width: 11, height: 11)
                                        : nil
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training activity, last \(Self.columns * Self.rows) days")
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
