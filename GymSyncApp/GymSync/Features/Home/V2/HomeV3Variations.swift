import SwiftUI

// MARK: - Home v3, ten variations
//
// The owner, after seeing the Home v2 A/B frames rendered (plan:
// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`): "there's
// goodness in both … the tile version of the start workout and check-in wins
// over the striped version … strip the detail sessions from the bottom of the
// training calendar … give me like 10 different mock ups."
//
// So: ten compositions of the same kit, all catalog-only. Three things are
// fixed across every one of them and are NOT what the owner is being asked to
// judge — they are what was already decided:
//
//   * the TOP ROW is arrangement A's. `HomeOneButton` full width, and on a
//     crew state the quiet `START SOLO WORKOUT` pill with the burpee counter
//     beside it (design language rule 5). B's today card is retired.
//   * the CALENDAR CARD has lost its folded itinerary
//     (`showsAppointments: false`) and gained the chevron that says it opens
//     the page where that itinerary is written out.
//   * the GREETING HEADER opens every page, and the JOIN-WITH-CODE card
//     closes it unless the plan's table ends that composition elsewhere.
//
// What varies is everything between: which readouts, in which form (tile or
// strip), in which order. Five compositions render the crew-night world and
// five the solo day, so both button states appear across the set and no
// single arrangement gets judged on one state alone.
//
// Ten views in one file because they are assemblies, not logic: each is a
// list of pieces with page margins, and ten near-identical files would hide
// the only thing worth reading here, which is the differences between them.
//
// ADDENDUM (plan: `docs/superpowers/plans/2026-09-06-home-v3-addendum
// -targets-strip.md`) — twelve now, because the owner picked 08 and asked
// for one more strip on it: "variation 8 of the Home Screen is great. Maybe
// above the join with code, we display the weekly muscle group goals, or
// whatever goal the coach is tracking as a strip?" So 08a and 08b are
// variation 08 with `HomeWeeklyGoalStrip` inserted, and the ONLY thing
// that differs between them is where it sits — above the calendar, or above
// the join card as the owner phrased it. They are a two-up pair of their
// own: what is being judged is the fold, not the strip.

// MARK: - Shared scaffolding

/// The frame every variation shares: the greeting, the fixed top row, then
/// whatever that variation puts underneath.
///
/// Lifted out rather than repeated ten times — a drifted copy of the top row
/// in one of ten frames would read to the owner as a design choice.
/// `HomeV2TilesView`'s own body (:20-38) is the source: same `ScrollView`,
/// same `spacing: 0` stack, same 9 pt gap between the button and the solo
/// row, same 16 pt page margins, same `scrollContentBackground(.hidden)` over
/// `theme.bg`.
private struct HomeV3Frame<Content: View>: View {
    @Environment(\.gsTheme) private var theme

    let world: HomeV2World
    private let content: Content

    init(world: HomeV2World, @ViewBuilder content: () -> Content) {
        self.world = world
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeV2GreetingHeader(greeting: world.greeting,
                                     dateLine: world.dateLine,
                                     initials: world.avatarInitials)

                VStack(spacing: 9) {
                    HomeOneButton(state: world.primary)
                    // Rule 5: the quiet solo pill stays under a crew primary,
                    // and the debt emerges beside it. A solo primary already
                    // opens the start screen, so the pill would be a second
                    // door to the same room.
                    if world.primary.isCrewState {
                        HomeSoloRow(burpeesOwed: world.burpeesOwed)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                content
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
    }
}

/// The two-column tile row (`HomeV2TilesView`, :43-50): equal heights,
/// because both tiles stretch to `maxHeight: .infinity` inside an `HStack`
/// that is `fixedSize(vertical: true)`, so the row sizes to the taller tile
/// and the shorter one fills. The gap is the plan's 10 pt.
private struct HomeV3TilePair<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: HomeV3Metrics.tileGap) {
            content
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The v3 training calendar: the dot field and the door handle, with the
/// itinerary moved to the page the card opens. Every composition uses this
/// one — the plan makes the folded rows a fixed decision, not a variable.
private struct HomeV3Calendar: View {
    let world: HomeV2World

    var body: some View {
        HomeCalendarCard(months: world.months,
                         appointments: world.appointments,
                         showsAppointments: false)
    }
}

private extension View {
    /// A card or a tile row on the page: 16 pt margins, 12 pt to the next
    /// thing — Home v2's rhythm, unchanged.
    func homeV3Block() -> some View {
        padding(.horizontal, 16).padding(.bottom, 12)
    }

    /// A strip on the page. Strips sit 2 pt tighter to what follows them
    /// than cards do, because a strip belongs to its neighbour rather than
    /// standing beside it (design language rule 1) — `HomeV2StripsView`
    /// (:34) makes the same call with the same number.
    func homeV3Strip() -> some View {
        padding(.horizontal, 16).padding(.bottom, 10)
    }

    /// The last block on a page that does NOT end with the join-with-code
    /// card: that card carries its own 24 pt foot (`HomeV2JoinCodeCard`,
    /// :44), and a page ending without it should not end 12 pt from the
    /// scroll's edge.
    func homeV3Foot() -> some View {
        padding(.horizontal, 16).padding(.bottom, 24)
    }
}

// MARK: - 01 · tiles (crew night)

/// `home-v3-01-tiles` — the tile answer, both above and below the calendar.
/// Streak and Coach in the first row, the two backward/forward readouts in
/// the second. The densest of the ten.
struct HomeV3TilesView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeV3TilePair {
                HomeStreakTile(streak: world.streak,
                               daysDone: world.daysDone,
                               goal: world.weeklyGoal)
                HomeCoachTile(sentence: world.coachSentence,
                              waiting: world.coachWaiting)
            }
            .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV3TilePair {
                HomeLastLiftTile(routine: HomeV2Fixtures.lastLiftRoutine,
                                 detail: HomeV2Fixtures.lastLiftDetail)
                HomePRWatchTile(lift: HomeV2Fixtures.prWatchLift,
                                invitation: HomeV2Fixtures.prWatchInvitation)
            }
            .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 02 · strips (solo day)

/// `home-v3-02-strips` — the strip answer. Everything under the button is a
/// line: the week, Coach, what's next. The quietest of the ten, and the one
/// that tests whether the button alone is enough of a hero.
struct HomeV3StripsView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeWeekStrip(streak: world.streak,
                          days: world.weekDays,
                          daysDone: world.daysDone,
                          goal: world.weeklyGoal)
                .homeV3Strip()

            HomeCoachLine(sentence: world.coachSentence)
                .homeV3Strip()

            // The SOLO day's next row, not the crew night's: this strip only
            // ever renders on a solo frame, and that world's calendar shows
            // Today / Tue / Thu with no Saturday anywhere in it.
            HomeUpNextStrip(kicker: HomeV2Fixtures.soloDayUpNext.kicker,
                            title: HomeV2Fixtures.soloDayUpNext.title)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 03 · week + tiles (crew night)

/// `home-v3-03-week-tiles` — the week as a strip so the tile row can spend
/// both of its slots on something else: Coach beside the last session.
struct HomeV3WeekTilesView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeWeekStrip(streak: world.streak,
                          days: world.weekDays,
                          daysDone: world.daysDone,
                          goal: world.weeklyGoal)
                .homeV3Block()

            HomeV3TilePair {
                HomeCoachTile(sentence: world.coachSentence,
                              waiting: world.coachWaiting)
                HomeLastLiftTile(routine: HomeV2Fixtures.lastLiftRoutine,
                                 detail: HomeV2Fixtures.lastLiftDetail)
            }
            .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 04 · tiles then a line (solo day)

/// `home-v3-04-tile-line` — one tile row, one Coach line, and the next
/// session AFTER the calendar rather than before it, so the page ends on
/// what happens next instead of on a form field.
struct HomeV3TileLineView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeV3TilePair {
                HomeStreakTile(streak: world.streak,
                               daysDone: world.daysDone,
                               goal: world.weeklyGoal)
                HomePRWatchTile(lift: HomeV2Fixtures.prWatchLift,
                                invitation: HomeV2Fixtures.prWatchInvitation)
            }
            .homeV3Block()

            HomeCoachLine(sentence: world.coachSentence)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Strip()

            // The SOLO day's next row, not the crew night's: this strip only
            // ever renders on a solo frame, and that world's calendar shows
            // Today / Tue / Thu with no Saturday anywhere in it.
            HomeUpNextStrip(kicker: HomeV2Fixtures.soloDayUpNext.kicker,
                            title: HomeV2Fixtures.soloDayUpNext.title)
                .homeV3Foot()
        }
    }
}

// MARK: - 05 · recovery (crew night)

/// `home-v3-05-recovery` — three strips in a stack: what the week has been,
/// what the body is ready for, what Coach makes of it. The one composition
/// where the readouts argue with each other, which is the point.
struct HomeV3RecoveryView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeWeekStrip(streak: world.streak,
                          days: world.weekDays,
                          daysDone: world.daysDone,
                          goal: world.weeklyGoal)
                .homeV3Strip()

            HomeRecoveryStrip(fresh: HomeV2Fixtures.recoveryFresh,
                              tender: HomeV2Fixtures.recoveryTender,
                              sentence: HomeV2Fixtures.recoverySentence)
                .homeV3Strip()

            HomeCoachLine(sentence: world.coachSentence)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 06 · milestone (solo day)

/// `home-v3-06-milestone` — the streak beside the lifetime total, so the
/// two long-run numbers sit together: one that resets and one that never
/// does.
struct HomeV3MilestoneView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeV3TilePair {
                HomeStreakTile(streak: world.streak,
                               daysDone: world.daysDone,
                               goal: world.weeklyGoal)
                HomeMilestoneTile(total: HomeV2Fixtures.milestoneTotal,
                                  line: HomeV2Fixtures.milestoneLine,
                                  progress: HomeV2Fixtures.milestoneProgress)
            }
            .homeV3Block()

            HomeCoachLine(sentence: world.coachSentence)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 07 · body (crew night)

/// `home-v3-07-body` — the body's own numbers in the tile row: what you
/// weigh and what you are about to lift. Ends on the calendar; no join card,
/// per the plan's table.
struct HomeV3BodyView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeWeekStrip(streak: world.streak,
                          days: world.weekDays,
                          daysDone: world.daysDone,
                          goal: world.weeklyGoal)
                .homeV3Block()

            HomeV3TilePair {
                HomeBodyWeightTile(weight: HomeV2Fixtures.bodyWeight,
                                   change: HomeV2Fixtures.bodyWeightChange)
                HomePRWatchTile(lift: HomeV2Fixtures.prWatchLift,
                                invitation: HomeV2Fixtures.prWatchInvitation)
            }
            .homeV3Block()

            HomeCoachLine(sentence: world.coachSentence)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Foot()
        }
    }
}

// MARK: - 08 · crew (crew night)

/// `home-v3-08-crew` — 01's tile row with the crew's pulse under it: on a
/// night when other people are involved, who is already there is the fact
/// that moves you.
struct HomeV3CrewView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeV3TilePair {
                HomeStreakTile(streak: world.streak,
                               daysDone: world.daysDone,
                               goal: world.weeklyGoal)
                HomeCoachTile(sentence: world.coachSentence,
                              waiting: world.coachWaiting)
            }
            .homeV3Block()

            HomeCrewPulseStrip(initials: HomeV2Fixtures.crewPulseInitials,
                               headline: HomeV2Fixtures.crewPulseHeadline,
                               detail: HomeV2Fixtures.crewPulseDetail)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 08a · targets above the calendar (crew night)

/// `home-v3-08a-targets-above-calendar` — 08 with Coach's targets between
/// the crew pulse and the calendar, so the page answers "what the week asks
/// of you" while the reader is still at the top of it and the calendar's
/// "when" lands straight after.
///
/// The crew pulse takes `homeV3Strip()` here where 08 gives it
/// `homeV3Block()`. That is the spacing law these compositions already
/// follow rather than a new decision: the 2 pt-tighter gap goes BEFORE a
/// strip (02 and 05 pair their strips that way; 04 and 10 tighten even the
/// calendar card when a strip follows it), and what follows the pulse here
/// is the targets strip.
struct HomeV3TargetsAboveCalendarView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeV3TilePair {
                HomeStreakTile(streak: world.streak,
                               daysDone: world.daysDone,
                               goal: world.weeklyGoal)
                HomeCoachTile(sentence: world.coachSentence,
                              waiting: world.coachWaiting)
            }
            .homeV3Block()

            HomeCrewPulseStrip(initials: HomeV2Fixtures.crewPulseInitials,
                               headline: HomeV2Fixtures.crewPulseHeadline,
                               detail: HomeV2Fixtures.crewPulseDetail)
                .homeV3Strip()

            HomeWeeklyGoalStrip(kind: .muscleSets,
                                progress: HomeV2Fixtures.coachTargetsProgress)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 08b · targets above the join card (crew night)

/// `home-v3-08b-targets-above-join` — the owner's own placement: under the
/// calendar, above join-with-code. The page then ends on what the week still
/// owes instead of on a form field, and on a small device the strip sits
/// below the fold. Which of those two facts matters more is exactly what
/// this frame and 08a exist to ask.
///
/// The calendar takes `homeV3Strip()` here for the reason 04 and 10 give it
/// the same modifier: the tighter gap goes before a strip.
struct HomeV3TargetsAboveJoinView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeV3TilePair {
                HomeStreakTile(streak: world.streak,
                               daysDone: world.daysDone,
                               goal: world.weeklyGoal)
                HomeCoachTile(sentence: world.coachSentence,
                              waiting: world.coachWaiting)
            }
            .homeV3Block()

            HomeCrewPulseStrip(initials: HomeV2Fixtures.crewPulseInitials,
                               headline: HomeV2Fixtures.crewPulseHeadline,
                               detail: HomeV2Fixtures.crewPulseDetail)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Strip()

            HomeWeeklyGoalStrip(kind: .muscleSets,
                                progress: HomeV2Fixtures.coachTargetsProgress)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 09 · plan (solo day)

/// `home-v3-09-plan` — the week named rather than counted, at the top, so
/// the page opens with the plan and the tile row underneath is the reward
/// for keeping it.
struct HomeV3PlanView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeWeekPlanStrip(entries: HomeV2Fixtures.weekPlan)
                .homeV3Block()

            HomeV3TilePair {
                HomeStreakTile(streak: world.streak,
                               daysDone: world.daysDone,
                               goal: world.weeklyGoal)
                HomeCoachTile(sentence: world.coachSentence,
                              waiting: world.coachWaiting)
            }
            .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Block()

            HomeV2JoinCodeCard()
        }
    }
}

// MARK: - 10 · minimal (solo day)

/// `home-v3-10-minimal` — the shortest page in the set: the button, the
/// week, Coach, the calendar, what's next. Four readouts, no tiles, no join
/// card. If the owner picks this one, everything else was decoration.
struct HomeV3MinimalView: View {
    let world: HomeV2World

    var body: some View {
        HomeV3Frame(world: world) {
            HomeWeekStrip(streak: world.streak,
                          days: world.weekDays,
                          daysDone: world.daysDone,
                          goal: world.weeklyGoal)
                .homeV3Strip()

            HomeCoachLine(sentence: world.coachSentence)
                .homeV3Block()

            HomeV3Calendar(world: world)
                .homeV3Strip()

            // The SOLO day's next row, not the crew night's: this strip only
            // ever renders on a solo frame, and that world's calendar shows
            // Today / Tue / Thu with no Saturday anywhere in it.
            HomeUpNextStrip(kicker: HomeV2Fixtures.soloDayUpNext.kicker,
                            title: HomeV2Fixtures.soloDayUpNext.title)
                .homeV3Foot()
        }
    }
}
