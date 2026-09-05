import SwiftUI

/// Home v2, arrangement **A — tiles**.
///
/// The one button, then a pair of square tiles (streak | Coach), then the
/// folded calendar. Everything above the fold is a question the lifter can
/// answer with one tap; the readouts sit below it (design language rule 4).
///
/// Order (plan, Task 2): greeting → the one button → `START SOLO WORKOUT` +
/// the burpee counter → the tile pair → the training calendar → join with
/// code.
///
/// Catalog-only: fixture inputs, no `AppState`, no repository call, and every
/// tap is a no-op — each piece names its real destination in its own comment.
struct HomeV2TilesView: View {
    @Environment(\.gsTheme) private var theme

    let world: HomeV2World

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeV2GreetingHeader(greeting: world.greeting,
                                     dateLine: world.dateLine,
                                     initials: world.avatarInitials)

                VStack(spacing: 9) {
                    HomeOneButton(state: world.primary)
                    // Rule 5: the quiet solo pill stays under a crew primary —
                    // and the debt emerges beside it. A solo primary already
                    // opens the start screen, so the pill would be a second
                    // door to the same room.
                    if world.primary.isCrewState {
                        HomeSoloRow(burpeesOwed: world.burpeesOwed)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // Equal heights: both tiles stretch to `maxHeight: .infinity`
                // inside an HStack that is `fixedSize(vertical: true)`, so the
                // row sizes to the taller tile and the shorter one fills.
                HStack(alignment: .top, spacing: 11) {
                    HomeStreakTile(streak: world.streak,
                                   daysDone: world.daysDone,
                                   goal: world.weeklyGoal)
                    HomeCoachTile(sentence: world.coachSentence,
                                  waiting: world.coachWaiting)
                }
                .fixedSize(horizontal: false, vertical: true)
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
}
