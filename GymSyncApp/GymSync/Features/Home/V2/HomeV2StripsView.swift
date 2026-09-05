import SwiftUI

/// Home v2, arrangement **B — strips**.
///
/// One raised object at the top — today's card, carrying the one button — and
/// everything under it a strip that belongs to it (design language rule 1).
///
/// Order (plan, Task 3): greeting → the today card → the week strip → the
/// Coach line → the training calendar → join with code.
///
/// Catalog-only: fixture inputs, no `AppState`, no repository call, and every
/// tap is a no-op — each piece names its real destination in its own comment.
struct HomeV2StripsView: View {
    @Environment(\.gsTheme) private var theme

    let world: HomeV2World

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeV2GreetingHeader(greeting: world.greeting,
                                     dateLine: world.dateLine,
                                     initials: world.avatarInitials)

                todayCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                HomeWeekStrip(streak: world.streak,
                              days: world.weekDays,
                              daysDone: world.daysDone,
                              goal: world.weeklyGoal)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                HomeCoachLine(sentence: world.coachSentence)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                HomeCalendarCard(months: world.months,
                                 appointments: world.appointments)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                HomeV2JoinCodeCard()
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
    }

    /// Today, as one raised object: what today is, which week of the block it
    /// belongs to, the lift, its shape, and the one button. STATIC extrusion
    /// (`.gs3DCard`) — the button inside is the tappable, and a button inside a
    /// tappable card is the gesture conflict this codebase already avoids.
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(world.todayKicker)
                    .font(GSFont.bold(10.5, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(world.todayPill)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.2)
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.neutral300))
            }

            Text(world.todayTitle)
                .font(GSFont.heading(28, relativeTo: .title))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 10)

            Text(world.todayLine)
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HomeOneButton(state: world.primary)
                .padding(.top, 14)

            escapeHatch
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    /// The way out of today's plan. A solo primary already opens the start
    /// screen, so one quiet invitation line is enough; a CREW primary gets
    /// rule 5's `START SOLO WORKOUT` pill instead — which is also the only
    /// place the burpee counter can surface in this arrangement.
    @ViewBuilder
    private var escapeHatch: some View {
        if world.primary.isCrewState {
            HomeSoloRow(burpeesOwed: world.burpeesOwed)
        } else {
            (
                Text(HomeV2Fixtures.somethingElsePrefix)
                    .font(GSFont.body(12.5, relativeTo: .caption))
                    .foregroundColor(theme.neutral500)
                + Text(HomeV2Fixtures.somethingElseAction)
                    .font(GSFont.bold(12.5, relativeTo: .caption))
                    .foregroundColor(theme.accent)
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
