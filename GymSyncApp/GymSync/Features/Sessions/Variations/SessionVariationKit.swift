#if DEBUG
import SwiftUI

// MARK: - The focused session design round — shared kit
//
// Spec: `docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md`
// (§1–§4, §7, §8 and the fifteen owner decisions). Design language:
// `docs/superpowers/specs/2026-09-05-design-language.md`. Brief: the focused
// design round, fourteen catalog-only ids.
//
// CATALOG-ONLY, exactly like the Home v3 round this copies. Nothing in this
// folder is reachable from the running app: every view here is rendered only
// through `CatalogHostView`, from the pinned fixtures below, and the whole
// folder is `#if DEBUG`. `LobbyView`, `SessionLiveView` and
// `WarmUpPhaseView` are untouched — spec §8 puts their rework in Phases A
// and B, AFTER the owner picks a composition here.
//
// WHAT IS FIXED ACROSS THE FOURTEEN, and is therefore NOT what the owner is
// being asked to judge:
//
//   * ONE WORLD. One crew (Push Crew), one block (Bench 225 by Oct 18, week
//     3 of 8), one set of people. A difference between two frames is the
//     composition, never a different cast.
//   * ONE ACCENT ACT PER SCREEN (design rule 4). Each view's doc comment
//     names where its accent went and why. The talk dock's small resting
//     waveform is NOT counted: it belongs to `PTTDockRow`, which every
//     shipped crew surface already pairs with a primary.
//   * NO GOLD ANYWHERE. Gold has two jobs (rule 2) — the week-streak number
//     and the open check-in window — and no frame in this round is in either
//     state: the lobby's viewer has already checked in.
//   * NO MINTED COMPONENTS. `gs3DCard` / `gs3DCardStyle`, `GSStatTile`,
//     `GSGoalChip`, `GSTag`, `GSTagStyle`, `PTTDockRow`, `GSInitialsAvatar`,
//     `GSHeartRatePill`, `GSSectionHeader`, `GSPrimaryButtonStyle`,
//     `Color.gsSuccess`. The pieces below are ARRANGEMENTS of those, not new
//     surfaces — the two radii (24 cards / 16 small cards), 14 pt strips and
//     999 pt pills are the language's, unchanged.
//   * NO EMOJI GLYPHS. SF Symbols throughout. The one exception is the
//     pump card's reaction row, where emoji are content (rule 2).
//
// HERMETIC. Every name, number and duration below is a literal. No clock is
// read (`Date()` appears nowhere in this folder), no network, no repository,
// no `AppState`. Two animations survive and are named where they are used:
// `GSHeartRatePill`'s own beat, and `PTTDockRow`'s resting waveform. Both
// are the shipped components' behaviour, and both already render in the
// `heart-rate-pill` and `voice-idle` captures.

// MARK: - Vocabulary

/// Spec §1: a lifter with the lobby open outside the gym's geofence is *on
/// the way*; inside it, *at the gym*; *checked in* once they tap (or the
/// geofence confirms). Owner decision 12 pins the first one.
enum SVStage: Equatable {
    case onTheWay
    case atTheGym
    case checkedIn

    /// The kicker spelling — caps, because it is a kicker (rule 3).
    var caps: String {
        switch self {
        case .onTheWay:  return "ON THE WAY"
        case .atTheGym:  return "AT THE GYM"
        case .checkedIn: return "CHECKED IN"
        }
    }

    /// SF Symbol, never an emoji (rule 2).
    var glyph: String {
        switch self {
        case .onTheWay:  return "figure.walk"
        case .atTheGym:  return "mappin.and.ellipse"
        case .checkedIn: return "checkmark.circle.fill"
        }
    }
}

/// One person in this round's world.
///
/// `isReady` is DELIBERATELY INDEPENDENT of `stage`. Spec §3.1 derives the
/// stage from "`check_in_state` plus the geofence/travel signals the lobby
/// already has", and owner decision 12 makes the difference between *at the
/// gym* and *checked in* a geofence fact — while readiness is a tap. So a
/// lifter standing in the room can have marked ready before the circle
/// confirms them, which is how the brief's fixture reads "2 of 4 ready" over
/// a track holding one ON THE WAY, two AT THE GYM and one CHECKED IN. The
/// frames therefore carry TWO signals: the stage says where you are, the
/// green tick says you are ready. See this file's report for the flag.
struct SVLifter: Identifiable {
    let id: Int
    let name: String
    var stage: SVStage = .checkedIn
    var isReady: Bool = false
    var isYou: Bool = false
    /// Spec §3.4 mode 2 — a personal scale-down, never broadcast, visible
    /// only where the crew already looks: under this person's avatar in
    /// "who's up next". `nil` for everyone whose prescription is the crew's.
    var scaleDown: String? = nil
    /// Owner decision 13: Together sessions share heart rate by default.
    var bpm: Int? = nil
    /// Rounds: has this lifter logged the current round's set?
    var hasLogged: Bool = false
    /// Round 2, the lobby's buy-in widget: self-reported energy, 1 to 5.
    /// `nil` = has not answered yet. Additive and defaulted, so no round-1
    /// frame changes — the v1 ids are frozen and the owner has approved
    /// their renders.
    var energy: Int? = nil
}

// MARK: - The world

/// Every literal the fourteen frames render. One crew, one block, one cast.
enum SVFixtures {

    static let crewName = "Push Crew"

    // MARK: Rounds (ids 7–10)

    /// Rack A: you + Sam + Dana. You have logged, Sam is lifting, Dana has
    /// logged. Sam carries spec §3.4 mode 2's quiet personal scale-down.
    static let rackA: [SVLifter] = [
        SVLifter(id: 1, name: "Alex Rue", isYou: true, hasLogged: true),
        SVLifter(id: 3, name: "Sam Obi", scaleDown: "Goblet squat", hasLogged: false),
        SVLifter(id: 2, name: "Dana Kord", hasLogged: true),
    ]

    /// Rack B: Lee + Mo. Rotation never deeper than three (owner decision 2).
    static let rackB: [SVLifter] = [
        SVLifter(id: 4, name: "Lee Vance", hasLogged: false),
        SVLifter(id: 5, name: "Mo Adeyemi", hasLogged: true),
    ]

    static let roundNumber = "ROUND 3"
    static let restElapsed = "1:42"
    static let hrFrom = 128
    static let hrTo = 96
    static let nextPrescription = "Set 3 of 4 · Back squat 225 × 5"
    /// The rest screen's "is the plan still achievable" check (spec §2).
    static let achievability = "Set 2 moved at 225. The plan still holds."
    static let stationALine = "you, Sam, Dana"
    static let stationBLine = "Lee, Mo"

    /// §9a, in the copy the spec writes for it: one quiet line, and any
    /// crewmate can tap it.
    static let skipOffer = "Sam's still resting — go ahead without him?"
    /// §9a's rule, made legible: the threshold is the crew's own median rest
    /// × 1.5 (floor 90 s, cap 180 s), measured from the second-to-last log.
    static let skipWaited = "Waited 2:31 — past the 2:24 the crew's own rest sets."
    static let skipConsequence = "Nothing is recorded against him. He rejoins next round."

    // MARK: Spotter (id 10)

    static let spotterRound = "ROUND 4"
    static let spotterLine = "Your plan has no set this round."
    static let spotterLifting = "Dana Kord"
    static let spotterNext = "Lee Vance"

    // MARK: Freestyle (id 11)

    static let freestyleTotal = 18
    static let freestyleRail: [(name: String, done: Int, isYou: Bool)] = [
        ("You", 14, true),
        ("Dana", 12, false),
        ("Lee", 12, false),
        ("Sam", 11, false),
    ]
    static let freestyleRest = "2:30"
    static let freestyleStretch = "Stretched 45 s so the crew finishes together."
    static let freestyleSuggestion = SVSuggestion(
        line: "while they catch up — 3×12 face pulls? It fits your shoulder week.",
        accept: "Add it",
        decline: "Not today")

    // MARK: Together (id 12)

    static let togetherTitle = "HIIT · 40 / 20"
    static let togetherRound = "ROUND 6 OF 12"
    static let togetherPhase = "WORK"
    static let togetherRemaining = "0:18"
    /// 22 of the 40 work-seconds are gone. Pinned, not computed from a clock.
    static let togetherProgress: Double = 22.0 / 40.0

    /// Four lifters on ONE timeline: twelve slots, one per round, the same
    /// axis for everybody. Round 6 is the live one, so slots 7-12 are empty.
    static let togetherTimeline: [(name: String, bpm: Int, trace: [Int])] = [
        ("You",   168, [118, 141, 152, 158, 163, 168, 0, 0, 0, 0, 0, 0]),
        ("Dana",  154, [112, 132, 143, 149, 151, 154, 0, 0, 0, 0, 0, 0]),
        ("Sam",   176, [124, 148, 161, 168, 172, 176, 0, 0, 0, 0, 0, 0]),
        ("Lee",   139, [104, 121, 128, 134, 137, 139, 0, 0, 0, 0, 0, 0]),
    ]

    // MARK: The consensus swap (id 13)

    static let swapProposer = "Dana Kord"
    static let swapFrom = "Back squat"
    static let swapTo = "Front squat"
    static let swapAgreed = 2
    static let swapCrewSize = 4
    static let swapAgreedBy = ["Dana Kord", "Mo Adeyemi"]

    // MARK: The pump card, v2 (id 14)
    //
    // The SAME VALUES `pump-feed-post` renders (CatalogHostView's
    // `pumpFixtureSummary` / `pumpFixtureTrajectory` / `pumpFixtureHighlight`),
    // so the two frames are a before/after of the composition and of nothing
    // else. Spelled as literals rather than built from `WorkoutPost`: the
    // shipped card's photo block runs a signed-URL `.task`, and a hermetic
    // frame may not.

    static let pumpAuthor = "Maya Iyer"
    static let pumpWhen = "1 hour ago"
    static let pumpLateTag = "posted 47 min after"
    static let pumpRetakeTag = "2 retakes"
    static let pumpTrajectory = "Bench 225 by Oct 18 · week 3 of 8 · behind"
    static let pumpChips: [(name: String, done: Double, target: Double)] = [
        ("CHEST", 8, 12), ("BACK", 10, 12), ("LEGS", 6, 12), ("ARMS", 8, 8),
    ]
    static let pumpHighlight = "235 × 3 on Back squat"
    static let pumpHighlightNote = "a personal record"
    static let pumpDetail = "Back squat 225 × 5, 235 × 3 · Walking lunge × 20"
    static let pumpPlain = "Push day · 42 min · 7,240 lb · avg 142 · max 171 bpm"
    static let pumpReactions: [(emoji: String, count: Int)] = [
        ("💪", 1), ("🔥", 3), ("👏", 0), ("🏆", 0), ("⚡", 0),
    ]
}

/// One suggestion: Coach's line and the two words that answer it. Owner
/// decision 4 — every weight, volume or set change is a suggestion the
/// athlete accepts, so a suggestion ALWAYS ships both answers, and neither
/// of them is the screen's accent (the primary is the physical act).
struct SVSuggestion {
    let line: String
    let accept: String
    let decline: String
}

// MARK: - Surfaces

/// A strip: `surface`, 14 pt, no extrusion — design rule 1's "lines that
/// belong to the card above them". Lifted as a modifier rather than a
/// wrapper view so a strip can be applied to whatever shape a frame needs.
struct SVStripModifier: ViewModifier {
    @Environment(\.gsTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    /// See `SVStripModifier`.
    func svStrip() -> some View { modifier(SVStripModifier()) }
}

/// The page every session frame is drawn on: a kicker, a title, the body,
/// then the foot (the talk dock and the one primary, in that order — rule 6
/// gives the talk control its home directly above the primary button).
///
/// A fixed page, not a `ScrollView`: the live session is a fixed page in the
/// shipped app, and rule 4's "questions above the fold" is only checkable in
/// a frame that HAS a fold.
struct SVScreen<Content: View, Foot: View>: View {
    @Environment(\.gsTheme) private var theme

    private let kicker: String
    private let title: String
    private let content: Content
    private let foot: Foot

    init(kicker: String,
         title: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder foot: () -> Foot) {
        self.kicker = kicker
        self.title = title
        self.content = content()
        self.foot = foot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                GSSectionHeader(kicker)
                Text(title)
                    .font(GSFont.bold(26, relativeTo: .title2))
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 14)

            VStack(alignment: .leading, spacing: 10) {
                foot
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
    }
}

// MARK: - Coach's suggestion

/// Coach's line plus the two answers, drawn either bare (inside
/// `SVSuggestionStrip`, below) or embedded by a caller of its own. Used to
/// be shared with an in-card form too (`SVPlanCard`, retired with
/// `warmup-solo-a`/`-b` in the group-session Phase A round, task S11); this
/// is what remains.
struct SVSuggestionBody: View {
    @Environment(\.gsTheme) private var theme

    let suggestion: SVSuggestion
    /// Spec §3.2: in a crew, Coach speaks to each lifter privately. The
    /// frame has to say so or the crew reads it as broadcast.
    var isPrivate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachLine
            if isPrivate {
                Text("Only you see this.")
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
            HStack(spacing: 8) {
                SVQuietPill(title: suggestion.accept)
                SVQuietPill(title: suggestion.decline)
                Spacer(minLength: 0)
            }
        }
    }

    private var coachLine: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 9)
                .fill(theme.neutral300)
                .frame(width: 30, height: 30)
                .overlay(
                    Text("CO")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(theme.neutral700)
                )
            (
                Text("Coach: ")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                + Text(suggestion.line)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The suggestion as its own object, wrapped in a strip — the shape
/// Freestyle's nudge uses.
struct SVSuggestionStrip: View {
    let suggestion: SVSuggestion
    var isPrivate: Bool = false

    var body: some View {
        SVSuggestionBody(suggestion: suggestion, isPrivate: isPrivate)
            .svStrip()
    }
}

// MARK: - Controls

/// A neutral answer: the raised face, never accent. Two of these under a
/// suggestion is rule 4's "everything else the raised face".
struct SVQuietPill: View {
    let title: String

    var body: some View {
        Button(action: {}) {
            Text(title)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
    }
}

/// The screen's one primary. `enabled: false` renders
/// `GSPrimaryButtonStyle`'s inert 0.4-opacity face — the shipped disabled
/// treatment, not a hand-dimmed copy of it.
///
/// `note` is the line UNDER the button (the consensus count, the leader's
/// standing). Under, not inside: a button says exactly what happens (rule 9)
/// and "START · 2 of 4 ready" says two things.
struct SVPrimary: View {
    @Environment(\.gsTheme) private var theme

    let title: String
    var enabled: Bool = true
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: {}) {
                Text(title)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 16, verticalPadding: 15))
            .frame(maxWidth: .infinity)
            .disabled(!enabled)

            if let note {
                Text(note)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// A control that is NOT the next act — the round's soft gate. A raised
/// neutral face at rest, no accent, no travel: the crew holds this, not you.
struct SVGatedControl: View {
    @Environment(\.gsTheme) private var theme

    let title: String
    var glyph: String = "hourglass"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(GSFont.bold(14, relativeTo: .subheadline))
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.neutral700)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)
    }
}

/// A door: a small raised tile with a glyph and two words (rule 4). Three in
/// a row at most — the spotter frame uses two, because talk is the dock.
struct SVDoor: View {
    @Environment(\.gsTheme) private var theme

    let glyph: String
    let title: String
    /// The one door that is the screen's primary act paints its face accent
    /// and its ink in `theme.bg`, the way `GSPrimaryButtonStyle` does.
    var isPrimary: Bool = false

    /// nil hands `GS3DCardStyle` the theme's neutral raised pair; an accent
    /// face derives its own darker lip, the accent-button path.
    private var face: Color? {
        isPrimary ? theme.accent : nil
    }

    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: glyph)
                    .font(.system(size: 17, weight: .bold))
                Text(title)
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                    .lineLimit(1)
            }
            .foregroundStyle(isPrimary ? theme.bg : theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm,
                                    lipHeight: 5,
                                    face: face))
    }
}

// MARK: - People

/// One avatar with its optional readiness tick and its optional personal
/// scale-down line. `ring` is how a frame marks the CURRENT lifter (rule 2's
/// "the current item in a pager or turn strip") — the only accent a rounds
/// frame spends.
struct SVAvatarMark: View {
    @Environment(\.gsTheme) private var theme

    let lifter: SVLifter
    var size: CGFloat = 42
    var ring: Bool = false
    /// nil = accent, the current-item job. A frame that has spent its accent
    /// elsewhere (the skip offer, the spotter's CHEER) passes a neutral tone
    /// so the eye still finds the person without the page carrying two
    /// accents.
    var ringColor: Color? = nil
    var showsReady: Bool = false
    var showsLogged: Bool = false
    /// The column this mark occupies. nil = the avatar plus breathing room;
    /// the station cards pass a tighter number because two cards share the
    /// page width and a three-deep rotation has to fit inside one of them.
    var columnWidth: CGFloat? = nil

    var body: some View {
        VStack(spacing: 5) {
            avatar
            Text(lifter.isYou ? "You" : SVName.first(lifter.name))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let scaleDown = lifter.scaleDown {
                // Spec §3.4 mode 2: the personal scale-down, never broadcast,
                // visible only where the crew already looks. Two lines
                // allowed — a truncated substitution names nothing.
                Text(scaleDown)
                    .font(GSFont.body(10, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(width: columnWidth ?? (size + 24))
    }

    private var avatar: some View {
        GSInitialsAvatar(name: lifter.name, size: size)
            .overlay(alignment: .bottomTrailing) { badge }
            .overlay(ringOverlay)
    }

    /// A ROUNDED RECTANGLE, not a circle: `GSInitialsAvatar` clips itself to
    /// `RoundedRectangle(cornerRadius: size * 0.28)`, and a circular ring
    /// around a rounded square reads as a rendering bug.
    @ViewBuilder
    private var ringOverlay: some View {
        if ring {
            RoundedRectangle(cornerRadius: size * 0.28)
                .strokeBorder(ringColor ?? theme.accent, lineWidth: 2)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if showsReady && lifter.isReady {
            SVTick()
        } else if showsLogged && lifter.hasLogged {
            SVTick()
        }
    }
}

/// Green means done or present (rule 2). One tick, one meaning, everywhere
/// in this round.
struct SVTick: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.gsSuccess)
            .background(Circle().fill(theme.bg).frame(width: 12, height: 12))
    }
}

/// First name only, for the places a full name would wrap a 42 pt column.
enum SVName {
    static func first(_ full: String) -> String {
        String(full.split(separator: " ").first ?? "")
    }
}

// MARK: - Readouts

/// The recovery readout: where the heart was when the set ended, and where
/// it is now. Heart-rate colour is data colour and is exempt from the
/// accent/green/gold rules (rule 2's own ruling), but this readout is a
/// DELTA rather than a zone, so it is drawn in `text` and `gsSuccess` — the
/// arrival at recovered is "done", which is green's job.
struct SVRecoveryReadout: View {
    @Environment(\.gsTheme) private var theme

    let from: Int
    let to: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.neutral700)
            Text("\(from)")
                .font(GSFont.bold(17, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(theme.neutral500)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.neutral500)
            Text("\(to)")
                .font(GSFont.bold(17, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(Color.gsSuccess)
            Text("BPM")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
            Spacer(minLength: 0)
        }
    }
}

/// The elapsed-rest hero: the largest number on the rounds pages, with one
/// small unit beside it (rule 3).
struct SVRestClock: View {
    @Environment(\.gsTheme) private var theme

    let elapsed: String
    var caption: String = "ELAPSED REST"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GSSectionHeader(caption)
            Text(elapsed)
                .font(GSFont.bold(38, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
    }
}

/// The next prescription and the achievability check — spec §2's two other
/// rest-screen elements, always together, so a variation cannot silently
/// drop one.
struct SVNextUp: View {
    @Environment(\.gsTheme) private var theme

    let prescription: String
    let achievability: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GSSectionHeader("NEXT")
            Text(prescription)
                .font(GSFont.bold(15, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Text(achievability)
                .font(GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The two stations as one quiet line each — the form variation a uses,
/// where the stations are context rather than the subject.
struct SVStationLines: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            line("RACK A", SVFixtures.stationALine)
            line("RACK B", SVFixtures.stationBLine)
        }
        .svStrip()
    }

    private func line(_ name: String, _ people: String) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
                .frame(width: 52, alignment: .leading)
            Text(people)
                .font(GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
            Spacer(minLength: 0)
        }
    }
}

/// The heart-rate ramp, mirroring `GSHeartRatePill`'s own private mapping
/// (blue → green → orange → red over the four named zones). Heart-rate zone
/// colour is DATA COLOUR and is exempt from the accent/green/red rules —
/// design language rule 2 says so explicitly, and `GSHeartRatePill` is the
/// precedent.
///
/// MOVED HERE from `StyleVariations.swift` (plan task S13): that file's own
/// ten-ids-out deletion would have taken this definition with it, but
/// `SessionVariationsV2Kit.swift`'s `zoneTinted` still reads it
/// (`SVZoneColor.of(bpm)`) — a Kit symbol a surviving frame uses must not
/// leave with the file that used to declare it.
enum SVZoneColor {
    static func of(_ bpm: Int) -> Color {
        switch HeartRateZone.zone(bpm: bpm) {
        case .warmup:   return .blue
        case .moderate: return .green
        case .hard:     return .orange
        case .max:      return .red
        }
    }
}
#endif
