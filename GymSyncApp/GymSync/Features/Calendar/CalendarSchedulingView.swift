import SwiftUI

// MARK: - CalendarSchedulingView
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §C. Plan: docs/superpowers/plans/2026-09-06-home-v3
// -production-plan.md, task 0.4 (this scaffold) and Stream D (the page).
//
// The page `HomeCalendarCard` is a door onto. Design language rule 4:
// anything that lives on a timeline is visible on Home, or ONE TAP from the
// page where it is editable — this is that page, and the card's whole
// surface, its `+` and its status chips all land here.
//
// THIS COMMIT IS A SCAFFOLD, deliberately. It ships the chrome Stream B
// needs to push something real — the nav title, the month line, the `+`, and
// the one primary — and marks everything else for Stream D. The type name
// and the init are FIXED at this point: Stream B builds its push against
// them and Stream D fills the body in without touching either, which is the
// whole reason task 0 exists.
//
// No catalog id here. Stream D owns `calendar-scheduling` (frame 92) and the
// four-part contract that comes with it (plan constraint 3).

struct CalendarSchedulingView: View {
    /// The sessions the caller already fetched, so the page paints instantly
    /// from Home's `refresh()` results and re-fetches in the background.
    let completedSessions: [WorkoutSession]
    let upcomingSessions: [WorkoutSession]
    let groups: [GymGroup]

    @Environment(\.gsTheme) private var theme

    @State private var showScheduleSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(monthLine)
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral500)

                // Stream D — D1: the month grid (dots: trained = text,
                // scheduled you = accent ring, crew = crew colour ring, today
                // ring), swipeable by month, on `TrainingCalendarWidget`'s own
                // constants.
                // Stream D — D2: the selected week's agenda, one row per item
                // with time / routine / crew or Solo / status pill / chevron.
                // Stream D — D3: the block's days and campaign deadlines on
                // the same timeline.

                scheduleButton
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showScheduleSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.neutral300))
                }
                .accessibilityLabel("Schedule a session")
            }
        }
        .sheet(isPresented: $showScheduleSheet) {
            // The existing scheduler, unchanged — the design's §C says the
            // page's primary opens `ScheduleSessionView`, not a new one.
            // Stream D: fold the new session into the agenda here.
            ScheduleSessionView { _ in }
        }
    }

    /// The page's ONE primary (design language rule 4). The toolbar `+` is
    /// the same act as a 32 pt affordance rather than a second primary — it
    /// rides the accent glyph the calendar card already uses for it
    /// (`HomeCalendarCard`:134-138), so the door and the room agree.
    ///
    /// Extruded exactly like the sheet it opens
    /// (`ScheduleSessionView`:175-179): `.gs3D` on an accent face at
    /// `radiusSm`, label in `theme.bg`, 16/14 padding. Deliberately NOT
    /// `HomeV2Metrics`' 57/48 pt faces — those are Home's own row geometry,
    /// and a calendar page borrowing them would be the first cross-feature
    /// reader of that enum for no reason.
    private var scheduleButton: some View {
        Button {
            showScheduleSheet = true
        } label: {
            Text("SCHEDULE A SESSION")
                .font(GSFont.heading(16, relativeTo: .headline))
                .tracking(0.6)
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
    }

    /// `SEPTEMBER 2026`. Stream D replaces this with the swipeable month's
    /// own label — at which point it also stops reading the clock, which a
    /// catalog capture cannot afford (`calendar-scheduling` is D's id and its
    /// frame has to be hermetic).
    private var monthLine: String {
        Date.now.formatted(.dateTime.month(.wide).year()).uppercased()
    }
}
