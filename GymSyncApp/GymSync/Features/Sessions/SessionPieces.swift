import SwiftUI

// MARK: - SessionPieces
//
// Plan task S4. The production components the lobby (S7) and the warm-up
// screen (S9) share, built to the design round's approved frames:
// `lobby-crew-waiting-v2` (120), `lobby-crew-ready-v3` (127),
// `warmup-solo-v2` (122) and `warmup-crew` (111).
//
// They are those compositions with production types in place of `SVLifter` /
// `SVPlanRow`, and no `#if DEBUG`. **NOTHING HERE IMPORTS OR REFERENCES
// `Features/Sessions/Variations/`** — that folder is the design round's proof
// deck and S11 deletes most of it; a production screen that depended on it
// would be a production screen that stopped compiling.
//
// ONE PRIMARY PER SCREEN (rule 4) is enforced by composition, not by hope:
// none of these renders `GSPrimaryButtonStyle`. The lobby and the warm-up
// screen each place their own single primary in the foot.

// MARK: - The copy

/// Every literal these components print.
///
/// Copy that lives in a view body is copy nobody can review, so each string is
/// hoisted here and asserted in `SessionPiecesCopyTests`. Two surfaces print
/// several of them and a second copy is a copy that drifts.
enum SessionCopy {
    /// The arrival track's caption under a late lifter's tile (spec 3.1's
    /// late lane, `ArrivalLaw.isLate`). Review-final.md B2: `isLate` had no
    /// reader anywhere, so a late lifter read identically to one simply not
    /// yet arrived - this is the only thing that changes, and it is never a
    /// colour (design rule 2 reserves red for errors).
    static let late = "late"

    /// The plan card's kicker in the lobby (spec §3.1: the whole session).
    static let theSession = "THE SESSION"
    /// The energy card's kicker.
    static let howTheCrewFeels = "HOW THE CREW FEELS"
    /// The ask control, which belongs to whoever has not answered — you. The
    /// card never nags about somebody else.
    static let howAreYouFeeling = "How are you feeling?"
    /// An absence, never a zero (`EnergyMeter`).
    static let notYet = "not yet"
    /// The block strip's kicker.
    static let whereYouAre = "WHERE YOU ARE"
    /// The warm-up clock's kicker.
    static let warmingUp = "WARMING UP"
    /// The warm-up clock's trailing line: the phase has no target, which is
    /// spec §6's "warm-up is a phase, not a number" said to the athlete.
    static let noTargetGoWhenReady = "No target. Go when you're ready."
    /// The crew warm-up's readiness kicker.
    static let whosWarm = "WHO'S WARM"
    /// The same two words `GSConsentCard` uses, so a suggestion answers the
    /// same way everywhere in the app.
    static let accept = GSConsentCopy.accept
    static let decline = GSConsentCopy.decline
    /// Spec §3.2's "the Coach line for each lifter privately", said out loud on
    /// the CREW warm-up. The solo frame does not print it: nobody else is
    /// there, and "only you see this" on a screen with one lifter is noise.
    static let onlyYouSeeThis = "Only you see this."
    /// Coach's door (spec §3.6).
    static let talkToCoach = "Talk to Coach"
    static let talkToCoachDetail = "This session's focus · form questions · demo videos"
    /// The leader's one control on the whole plan card, before Start — flat
    /// furniture on a raised card. Fix round 3 R-7: replaces a `Swap` chip
    /// repeated on every row, which discarded the row it sat on and opened
    /// the same whole-routine picker regardless of which one was tapped.
    static let changeRoutine = "Change routine"
    /// THE CREW'S WEEK (owner addition 2026-09-12, on trial in Phase A).
    static let theCrewsWeek = "THE CREW'S WEEK"

    /// THE VERB THAT DID NOT HAPPEN (plan task S3). The live body's
    /// `errorText` covers ending the session, leaving it, the burpee ledger,
    /// the crew's skip and the re-mix — everything the lifter PRESSED that
    /// failed. It is deliberately not the entry card's line: `logSetErrorText`
    /// means "nothing was saved, try again" and holds the card up for the
    /// retry, which is the one thing a persisted set must never invite.
    static let verbFailed = "That didn't go through."
    /// It clears on tap, and on the next successful attempt. Said out loud,
    /// because a banner with no stated exit reads as a stuck warning.
    static let verbFailedDismiss = "TAP TO DISMISS"

    /// First name only, for the places a full name would wrap a 40 pt column.
    static func firstName(_ full: String) -> String {
        String(full.split(separator: " ").first ?? "")
    }

    /// What a lifter's own column says. "You" rather than your own name: the
    /// crew reads the row to find themselves in it.
    static func columnName(_ row: ArrivalRow) -> String {
        row.isYou ? "You" : firstName(row.name)
    }
}

// MARK: - The plan's rows

/// One exercise on the session's plan card.
///
/// The production analogue of `SVPlanRow`. A `RoutineExercise` carries an
/// exercise id and not a name — the name needs the catalog, which the lobby
/// already resolves through `exerciseName(for:)` — so the card takes rows that
/// are already worded and does no lookups of its own.
struct SessionPlanRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// Right-aligned and tabular: `3 × 5 @ 225`.
    let prescription: String
    /// The exercise the session is on right now. At most one row sets it.
    var isCurrent: Bool = false
    /// MID-SESSION ONLY (plan task S6): how far into this exercise the crew
    /// is. Read by `SessionPlanCard` when its `showsProgress` is on, and by
    /// nothing else — both are additive and defaulted, so the lobby's and the
    /// warm-up screen's approved frames render exactly as they did.
    var setsDone: Int = 0
    var sets: Int = 0
}

extension SessionPlanRow {

    /// One `RoutineExercise` as a plan row — the lobby (S7) and the warm-up
    /// screen (S9) both build rows this way, so the wording lives here rather
    /// than twice.
    ///
    /// The NAME is the caller's to supply: it needs the 1,300-row exercise
    /// catalog, which the two screens already hold and this file must not
    /// reach for (constraint 11).
    init(exercise: RoutineExercise, name: String, isCurrent: Bool = false) {
        self.init(id: exercise.id, name: name,
                  prescription: Self.prescription(for: exercise),
                  isCurrent: isCurrent)
    }

    /// `4 × 5 @ 225`, `3 × 8-12`, `Z2 · 20 min`, or the honest `—`.
    ///
    /// Cardio branches FIRST, on the presence of its own pair, because the
    /// generator writes `cardioZone`/`cardioMinutes` instead of sets and reps
    /// — a cardio row read as `sets × reps` prints a dash for a prescription
    /// that exists. A rep RANGE beats the legacy text field, which the
    /// generator fills with the same numbers less precisely.
    static func prescription(for exercise: RoutineExercise) -> String {
        if let zone = exercise.cardioZone, let minutes = exercise.cardioMinutes {
            return "Z\(zone) · \(minutes) min"
        }
        var reps: String?
        if let low = exercise.targetRepsLow, let high = exercise.targetRepsHigh {
            reps = low == high ? "\(low)" : "\(low)-\(high)"
        } else if let text = exercise.targetReps, !text.isEmpty {
            reps = text
        } else if exercise.targetFailure {
            // A prescribed failure IS the assignment (the failure doctrine),
            // so it is printed as the rep target rather than left blank.
            reps = "AMRAP"
        }

        var parts: [String] = []
        switch (exercise.targetSets, reps) {
        case let (sets?, reps?): parts.append("\(sets) × \(reps)")
        case let (sets?, nil):   parts.append("\(sets) × —")
        case let (nil, reps?):   parts.append(reps)
        case (nil, nil):         break
        }
        if let weight = exercise.targetWeight, !weight.isEmpty {
            parts.append("@ \(weight)")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }
}

/// One lifter in the crew warm-up's readiness row.
///
/// Its own value rather than `ArrivalRow`: arrival and warmth are different
/// facts about different phases, and a row that carried both would invite a
/// screen to draw the one it is not in.
struct SessionWarmthRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    let isYou: Bool
    /// `session_participants.warmup_ready`.
    let isWarm: Bool
}

// MARK: - The strip

/// The chrome every strip in these screens wears: `theme.surface`, 14 pt
/// radius — a strip, not a card (rule 1).
private struct SessionStripModifier: ViewModifier {
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

private extension View {
    func sessionStrip() -> some View { modifier(SessionStripModifier()) }
}

/// The corner radius of an avatar-sized tile at `size`.
///
/// `GSInitialsAvatar` clips itself to `RoundedRectangle(cornerRadius: size *
/// 0.28)`, so anything drawn BESIDE an avatar — the arrival track's empty
/// slot, Coach's `CO` tile — has to use the same ratio or it reads as a
/// different kind of thing. This file had three idioms for it (0.28, a
/// hard 9, a hard 10); now it has one (review finding F8).
private func tileRadius(_ size: CGFloat) -> CGFloat { size * 0.28 }

// MARK: - The arrival track

/// Who is where, as three fixed columns with a chevron between them —
/// `lobby-crew-waiting-v2`'s rail, and the lobby's ONLY presence signal
/// (spec §3.1, owner decision 16).
///
/// A STRIP, not a card (rule 1): it is something you read, and the lobby's
/// raised objects are the plan and the energy.
///
/// Three columns whether or not anybody is in them. An empty stage keeps its
/// column and draws a dashed tile the size of an avatar, so it reads as a
/// missing person rather than as a different kind of thing.
struct SessionArrivalTrack: View {
    @Environment(\.gsTheme) private var theme

    let rows: [ArrivalRow]

    private static let avatar: CGFloat = 30
    /// The empty slot matches the avatar's own clip, so the two read as the
    /// same shape rather than two different ones.
    private static let avatarRadius: CGFloat = tileRadius(30)

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            column(.onTheWay)
            chevron
            column(.atTheGym)
            chevron
            column(.checkedIn)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(theme.neutral400)
            .padding(.top, 16)
    }

    private func column(_ stage: ArrivalStage) -> some View {
        let people = rows.filter { $0.stage == stage }
        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: stage.glyph)
                    .font(.system(size: 9, weight: .bold))
                Text(stage.caps)
                    // 10 pt: design rule 3 puts kickers at 10-11, and 9 was
                    // below the floor the language sets (review finding F6).
                    // `minimumScaleFactor` below still lets `ON THE WAY` fit
                    // a third of the width on the narrowest device.
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.0)
            }
            .foregroundStyle(people.isEmpty ? theme.neutral500 : theme.neutral700)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if people.isEmpty {
                RoundedRectangle(cornerRadius: Self.avatarRadius)
                    .strokeBorder(theme.neutral400, lineWidth: 1)
                    .frame(width: Self.avatar, height: Self.avatar)
            } else {
                HStack(alignment: .top, spacing: -8) {
                    ForEach(people) { person in
                        VStack(spacing: 2) {
                            GSInitialsAvatar(name: person.name,
                                             avatarURL: person.avatarURL,
                                             size: Self.avatar)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Self.avatarRadius)
                                        .strokeBorder(theme.surface, lineWidth: 2)
                                )
                            // B2 (review-final.md): isLate had no reader
                            // anywhere, so a late lifter read identically to
                            // one simply not yet arrived. Never a colour -
                            // red is errors (design rule 2) - and the name
                            // stays exactly as it was, via the avatar's own
                            // initials.
                            if person.isLate {
                                Text(SessionCopy.late)
                                    .font(GSFont.body(10, relativeTo: .caption2))
                                    .foregroundStyle(theme.neutral700)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }

            Text(people.isEmpty ? "—" : "\(people.count)")
                .font(GSFont.bold(12, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(people.isEmpty ? theme.neutral500 : theme.text)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The plan

/// The whole routine, one row per exercise — `lobby-crew-waiting-v2`'s plan
/// card. A raised card, because the leader presses things on it.
///
/// A FIXED 28 pt row height, so four rows make four straight edges; and a
/// 3 pt gutter reserved whether or not a row is current, so the current
/// row's mark cannot shift the names out of their column.
struct SessionPlanCard: View {
    @Environment(\.gsTheme) private var theme

    let kicker: String
    /// Today's rung, above the rows: what the block asks of this session.
    let rungLine: String
    let rows: [SessionPlanRow]
    /// The leader's one control for the whole card, before Start (spec
    /// §3.1, fix round 3 R-7 — replaces a `Swap` chip repeated on every row,
    /// which discarded the row it sat on and opened the same whole-routine
    /// picker regardless of which one was tapped). Nil hides it: a
    /// crewmate, or the card once lifting has begun, gets no control at all
    /// — swapping mid-session is spec §3.4 mode 1's consensus card, and
    /// that is Phase B's.
    var onChangeRoutine: (() -> Void)?

    /// MID-SESSION (plan task S6): each row gains a `setsDone/sets` column.
    /// Defaulted off, so the lobby's and the warm-up screen's frames are
    /// untouched — the round wait is the only screen that turns it on, and
    /// the reason it is a flag on this card rather than a second card is
    /// spec §3.6's own reasoning about the Coach door: two drawings of one
    /// object is how two screens stop lining up.
    var showsProgress: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                GSSectionHeader(kicker)
                Spacer(minLength: 8)
                if let onChangeRoutine {
                    changeRoutineChip(onTap: onChangeRoutine)
                }
            }
            if !rungLine.isEmpty {
                Text(rungLine)
                    .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GSDivider()
            ForEach(rows) { row in
                SessionPlanRowView(row: row, showsProgress: showsProgress)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    /// A FLAT capsule chip on the raised card — furniture inside a raised box
    /// stays flat (rule 1). The same drawing the retired per-row `Swap` chip
    /// used, spent once per card instead of once per row.
    private func changeRoutineChip(onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold))
                Text(SessionCopy.changeRoutine)
                    .font(GSFont.bodyMedium(11, relativeTo: .caption2))
            }
            .foregroundStyle(theme.neutral700)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.neutral300)
            .clipShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// One plan row. Its own view rather than a method, because
/// `SessionPlanCardWithSuggestion` draws the same rows and two drawings of a
/// row is how two cards stop lining up.
private struct SessionPlanRowView: View {
    @Environment(\.gsTheme) private var theme

    let row: SessionPlanRow
    /// Plan task S6. Defaulted off — `SessionPlanCardWithSuggestion` and the
    /// lobby's card both draw the row exactly as they did.
    var showsProgress: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(row.isCurrent ? theme.text : Color.clear)
                .frame(width: 3, height: 16)

            Text(row.name)
                .font(row.isCurrent ? GSFont.bold(13.5, relativeTo: .subheadline)
                                    : GSFont.bodyMedium(13.5, relativeTo: .subheadline))
                .foregroundStyle(row.isCurrent ? theme.text : theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            Text(row.prescription)
                .font(GSFont.body(12, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(theme.neutral500)
                .fixedSize()

            // A FIXED 32 pt column, so four rows keep one right edge whether
            // or not a row's count is two digits (plan task S6).
            if showsProgress {
                Text("\(row.setsDone)/\(row.sets)")
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(row.isCurrent ? theme.text : theme.neutral500)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .frame(height: 28)
    }
}

/// The same rows, plus a divider and Coach's suggestion **inside** the card —
/// `warmup-solo-v2`'s composition.
///
/// A SEPARATE TYPE, not a boolean on `SessionPlanCard`: the suggestion's place
/// under a rule inside the card is `warmup-solo-b`'s whole argument, and a
/// flag would let a later edit quietly move it back out.
struct SessionPlanCardWithSuggestion: View {
    @Environment(\.gsTheme) private var theme

    let kicker: String
    /// The day's rung, large — the biggest thing on the warm-up screen is what
    /// you are about to lift.
    let rungHeadline: String
    let rungDetail: String
    let rows: [SessionPlanRow]
    /// Coach's readiness suggestion (plan task S8, spec §2 and §4). Nil renders
    /// the card with no suggestion and no rule, which is the shipped screen and
    /// the normal case.
    ///
    /// ONE VALUE, not two strings: a suggestion that does not say what it read
    /// is the thing Phase A deleted, so the two sentences travel together and a
    /// caller cannot half-fill them.
    var suggestion: WarmUpReadiness.Suggestion?
    var isPrivate: Bool = false
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            GSDivider()
            ForEach(rows) { row in
                SessionPlanRowView(row: row)
            }
            if let suggestion {
                GSDivider()
                suggestionBlock(suggestion)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    /// What was read, then what is proposed, then the two answers.
    ///
    /// NO ACCENT: the warm-up's accent is `START LIFTING` (design rule 2) and a
    /// suggestion is not the screen's act. Accept and Not today are both raised
    /// faces — `GSConsentCard`'s own pair, spelled the same way here, so a
    /// suggestion answers identically everywhere in the app.
    private func suggestionBlock(_ suggestion: WarmUpReadiness.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.read)
                .font(GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            Text(suggestion.proposal)
                .font(GSFont.bodyMedium(13.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if isPrivate {
                Text(SessionCopy.onlyYouSeeThis)
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
            HStack(spacing: 8) {
                answer(SessionCopy.accept, action: onAccept)
                answer(SessionCopy.decline, action: onDecline)
                // The faces hug their labels rather than splitting the width,
                // exactly as `GSConsentCard`'s pair does: two half-width
                // buttons read as a fork in the road, and this is a suggestion.
                Spacer(minLength: 0)
            }
        }
    }

    private func answer(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GSFont.bold(12.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            GSSectionHeader(kicker)
            Text(rungHeadline)
                .font(GSFont.bold(19, relativeTo: .title3))
                .foregroundStyle(theme.text)
            if !rungDetail.isEmpty {
                Text(rungDetail)
                    .font(GSFont.body(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
            }
        }
    }
}

// MARK: - The crew's energy

/// Each lifter's self-reported energy, as a group — the one buy-in widget the
/// lobby keeps now that the readiness roster is gone (owner decision 18).
///
/// Fixed 70 pt columns, so avatars and meters share baselines however long the
/// names are. The ask control is a RAISED FACE, never accent: the screen's
/// accent is Start.
struct CrewEnergyCard: View {
    @Environment(\.gsTheme) private var theme

    let rows: [ArrivalRow]
    /// `LobbyCopy.energyReported(reported:total:)`.
    let reported: String
    /// The control that belongs to whoever has not answered — you. Nil once I
    /// have answered; the card never nags about somebody else.
    var askTitle: String?
    var onAsk: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                GSSectionHeader(SessionCopy.howTheCrewFeels)
                Spacer(minLength: 8)
                Text(reported)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral700)
                    .fixedSize()
            }

            HStack(spacing: 0) {
                ForEach(rows) { row in
                    column(row)
                }
            }

            if let askTitle {
                Button(action: onAsk) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.mind.and.body")
                            .font(.system(size: 12, weight: .bold))
                        Text(askTitle)
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private func column(_ row: ArrivalRow) -> some View {
        VStack(spacing: 6) {
            GSInitialsAvatar(name: row.name, avatarURL: row.avatarURL, size: 34)
            Text(SessionCopy.columnName(row))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 13)
            EnergyMeter(value: row.energy)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70, alignment: .top)
    }
}

/// Five 6×8 pips at 3 pt spacing. `nil` draws the words `not yet`, never a
/// zero — an absence is not a reading of one.
///
/// No colour is spent on it: `text` filled, `neutral300` empty. Energy is not
/// an invitation, a warning or a completion, so it is none of the three
/// colours the language reserves.
struct EnergyMeter: View {
    @Environment(\.gsTheme) private var theme

    let value: Int?
    /// Drawn on an ACCENT face (`EveryoneHereCard`), so the pips invert: the
    /// page ground becomes the ink, exactly as `GSPrimaryButtonStyle` puts
    /// `theme.bg` on an accent fill.
    var onAccent: Bool = false

    private var filledInk: Color { onAccent ? theme.bg : theme.text }
    private var emptyInk: Color { onAccent ? theme.bg.opacity(0.3) : theme.neutral300 }
    private var absentInk: Color { onAccent ? theme.bg.opacity(0.7) : theme.neutral500 }

    var body: some View {
        Group {
            if let value {
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(step <= value ? filledInk : emptyInk)
                            .frame(width: 6, height: 8)
                    }
                }
            } else {
                Text(SessionCopy.notYet)
                    .font(GSFont.body(10, relativeTo: .caption2))
                    .foregroundStyle(absentInk)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Coach's door

/// One strip, one tap, a seeded thread (rule 7).
///
/// **NOT ACCENT.** Coach is reachable in one tap from everywhere; a door that
/// shouts on every screen it appears on stops being a door and becomes a
/// banner.
struct CoachDoorRow: View {
    @Environment(\.gsTheme) private var theme

    /// The door's three strings as ONE value (plan task S6).
    ///
    /// Spec §3.6 wants the Coach door "reachable from the lobby, the round
    /// wait and spotter mode" as one object in three places. The lobby passes
    /// its strings individually because it has always done so; the two live
    /// screens are value-in views (constraint 11) that carry their whole
    /// world as models, and this is the door's. Additive — no existing call
    /// site changes and nothing renders differently.
    struct Model: Equatable {
        let title: String
        let detail: String
        var note: String? = nil
    }

    let title: String
    let detail: String
    /// The line that says why this is not available — the crew's Coach thread
    /// is Pro, and this names whose it is waiting on.
    var note: String?
    var onTap: () -> Void = {}

    init(title: String, detail: String, note: String? = nil, onTap: @escaping () -> Void = {}) {
        self.title = title
        self.detail = detail
        self.note = note
        self.onTap = onTap
    }

    init(_ model: Model, onTap: @escaping () -> Void = {}) {
        self.init(title: model.title, detail: model.detail,
                  note: model.note, onTap: onTap)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: tileRadius(34))
                    .fill(theme.neutral300)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text("CO")
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundStyle(theme.neutral700)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GSFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text(detail)
                        .font(GSFont.body(11.5, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note)
                            .font(GSFont.body(10.5, relativeTo: .caption2))
                            .foregroundStyle(theme.neutral500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .sessionStrip()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Everyone's here

/// The all-ready arrival widget — `lobby-crew-ready-v3`'s accent slab.
///
/// It SINKS like every pressable (`.gs3DCardStyle` with an accent face), the
/// headline is `theme.bg`, and the avatars invert. **No green tick**: on an
/// accent slab a second colour is a second idea, and the sentence has already
/// said everyone is here.
///
/// Column geometry is identical to `CrewEnergyCard`'s but one size up — 44 pt
/// avatar, 13 pt name row, 12 pt meter, 80 pt column — because this is the
/// page's one accent object and the crew is what it is about.
struct EveryoneHereCard: View {
    @Environment(\.gsTheme) private var theme

    let rows: [ArrivalRow]
    /// `LobbyCopy.readyLeaderCaption` or `readyCrewmateCaption(_:)`.
    let caption: String
    /// The leader's tap starts the session. Everyone else's card is a
    /// readout, so it does not press and shows no chevron.
    var isTappable: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        if isTappable {
            Button(action: onTap) { slab }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd,
                                            lipHeight: 6,
                                            face: theme.accent))
        } else {
            slab.gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6,
                          face: theme.accent)
        }
    }

    private var slab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LobbyCopy.everyoneHere)
                .font(GSFont.bold(21, relativeTo: .title2))
                .foregroundStyle(theme.bg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(rows) { row in
                    column(row)
                }
            }
            captionRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ row: ArrivalRow) -> some View {
        VStack(spacing: 6) {
            GSInitialsAvatar(name: row.name, avatarURL: row.avatarURL, size: 44,
                             fill: theme.bg, ink: theme.accent)
            Text(SessionCopy.columnName(row))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.bg.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 13)
            EnergyMeter(value: row.energy, onAccent: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80, alignment: .top)
    }

    private var captionRow: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                .foregroundStyle(theme.bg.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isTappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.bg.opacity(0.85))
            }
        }
    }
}

// MARK: - The foot's secondary Start

/// Full-width raised neutral face with the note centred beneath — the foot's
/// Start once the accent has gone up the page.
///
/// Ink is `theme.text`, **not** the inert `neutral700` a gated control reads
/// in its label — this button's own opacity is what tells the two roles
/// apart. For the leader it renders enabled (full opacity, live tap); a
/// crewmate's caller passes `.disabled(true)` (fix round 3 R-2 —
/// `startSession()` has no organizer guard, so an ungated copy of this
/// button let any crewmate start the session), which `GS3DCardStyle` dims to
/// 0.5 opacity on its own. The crewmate's explanation lives on the widget
/// above (`LobbyCopy.readyCrewmateCaption`), not on this button's note.
///
/// THE NOTE ITSELF IS GATED TOO (review push-5 R-18, finding 11):
/// `GS3DCardStyle` only dims the button's own face, not this VStack's other
/// child — a plain `Text` does not dim on `isEnabled` by itself — so a
/// crewmate saw a full-opacity "Same action, in the thumb zone" caption
/// under a dead button. Reading `\.isEnabled` here (the same environment
/// value `.disabled(!isOrganizer)` sets at the call site) and hiding the
/// note when it is false makes the two speak the same truth: the caller's
/// note text is the LEADER's explanation of the live control, and a
/// crewmate's explanation is the widget's, not a second copy here.
struct SecondaryStartButton: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let note: String
    var onTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: onTap) {
                Text(title)
                    .font(GSFont.bold(16, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 5))

            if isEnabled {
                Text(note)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Who's warm

/// The crew warm-up's readiness — `warmup-crew`'s row of marked avatars.
///
/// A `Color.gsSuccess` tick on a lifter who has marked warm and nothing on one
/// who has not. Green means done or present, one tick, one meaning (rule 2).
struct SessionReadinessRow: View {
    @Environment(\.gsTheme) private var theme

    let rows: [SessionWarmthRow]
    let kicker: String
    /// "2 of 4 warm" — the count, already worded by the caller.
    let count: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GSSectionHeader(kicker)
                Spacer(minLength: 8)
                Text(count)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral700)
                    .fixedSize()
            }
            HStack(spacing: 4) {
                ForEach(rows) { row in
                    mark(row)
                }
                Spacer(minLength: 0)
            }
        }
        .sessionStrip()
    }

    private func mark(_ row: SessionWarmthRow) -> some View {
        VStack(spacing: 5) {
            GSInitialsAvatar(name: row.name, avatarURL: row.avatarURL, size: 40)
                .overlay(alignment: .bottomTrailing) {
                    if row.isWarm {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.gsSuccess)
                            .background(Circle().fill(theme.bg).frame(width: 12, height: 12))
                    }
                }
            Text(row.isYou ? "You" : SessionCopy.firstName(row.name))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 64)
    }
}

// MARK: - Where the block is

/// `WHERE YOU ARE` + `WEEK n OF m`: done rungs `text`, the current one taller,
/// the rest `neutral300`, and a neutral `flag.checkered` at the end.
///
/// **NO COLOUR.** A block you are 3/8 through is neither an invitation nor an
/// achievement.
struct BlockLadderStrip: View {
    @Environment(\.gsTheme) private var theme

    let week: Int
    let weeks: Int
    let milestone: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GSSectionHeader(SessionCopy.whereYouAre)
                Spacer(minLength: 8)
                Text("WEEK \(week) OF \(weeks)")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.text)
                    .monospacedDigit()
                    .fixedSize()
            }
            if weeks > 0 {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(1...weeks, id: \.self) { rung in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(rung <= week ? theme.text : theme.neutral300)
                            .frame(maxWidth: .infinity)
                            .frame(height: rung == week ? 18 : 10)
                    }
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize()
                }
                .frame(height: 20)
            }
            Text(milestone)
                .font(GSFont.bodyMedium(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
        }
        .sessionStrip()
    }
}

// MARK: - The warm-up clock

/// A STRIP at 18 pt, not a hero: the largest thing on the warm-up screen is
/// what you are about to lift, and the plan card's rung headline is 19.
///
/// `warmup_minutes` is not read here and there is no target — spec §6 retires
/// the number, and the clock that used to end the phase is now a readout.
struct WarmUpClockStrip: View {
    @Environment(\.gsTheme) private var theme

    /// Already formatted by the caller — `mm:ss`.
    let elapsed: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.neutral700)
            VStack(alignment: .leading, spacing: 1) {
                GSSectionHeader(SessionCopy.warmingUp)
                Text(elapsed)
                    // 18 pt, UNDER the plan card's 19 pt rung headline — this
                    // strip's own doc comment promises the largest thing on
                    // the warm-up screen is what you are about to lift, and at
                    // 22 the clock was contradicting it (review finding F7).
                    .font(GSFont.bold(18, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
            }
            Spacer(minLength: 0)
            Text(SessionCopy.noTargetGoWhenReady)
                .font(GSFont.body(11.5, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 128, alignment: .trailing)
        }
        .sessionStrip()
    }
}

// MARK: - The crew's week (owner addition 2026-09-12, controller ruling)

/// `THE CREW'S WEEK` — where the crew is against the pace it set itself.
///
/// **ON TRIAL.** The owner asked to see how this looks and feels on the Phase
/// A proof frames before it becomes permanent, so it is one self-contained
/// component over one value type (`CrewWeek`), placed by a single line in
/// `LobbyView.lobbyScroll` and removable by deleting that line.
///
/// **INK AND `neutral700` ONLY.** No accent, no green, no gold. Design rule 2
/// spends accent on the screen's one invitation (Start), green on done and
/// gold on the check-in window; a crew one session behind on a Wednesday is
/// none of the three. The verdict is a caption in WORDS, which is also the
/// only form a colour-blind reader gets for free.
///
/// Same surface treatment as the energy widget it sits under.
struct CrewWeekStrip: View {
    @Environment(\.gsTheme) private var theme

    let week: CrewWeek

    /// Small enough that it never competes with the plan above it — the
    /// largest thing in a lobby is what the crew is about to lift.
    private static let chartHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                GSSectionHeader(SessionCopy.theCrewsWeek)
                Spacer(minLength: 8)
                Text(CrewWeekMath.caption(week))
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.8)
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
                    .fixedSize()
            }
            chart
            chips
        }
        // Fix round 3 R-8: was five modifier lines duplicating
        // `SessionStripModifier` inline; every other strip in this file
        // already shares the one definition.
        .sessionStrip()
    }

    /// x is Monday…Sunday, y is the crew's cumulative sessions. The dotted
    /// line is the plan; the solid one is what happened, ending in a filled
    /// dot on today so the eye knows where "now" is on a week that has not
    /// finished.
    ///
    /// **EVERY CALCULATION IS A PLAIN FUNCTION BELOW, NOT A LOCAL ONE INSIDE
    /// THE `GeometryReader`.** Local `func`s with `return` statements in a
    /// `@ViewBuilder` closure do not compile — the builder cannot infer its
    /// `Content` and rejects the returns outright (CI at d513c94,
    /// SessionPieces.swift:987 and :998). The builder closure now contains
    /// nothing but view expressions, and the geometry is ordinary Swift that
    /// hands back `Path` and `CGPoint`.
    private var chart: some View {
        GeometryReader { proxy in
            ZStack {
                plannedPath(in: proxy.size)
                    .stroke(theme.neutral700,
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                actualPath(in: proxy.size)
                    .stroke(theme.text, style: StrokeStyle(lineWidth: 2,
                                                           lineCap: .round,
                                                           lineJoin: .round))
                Circle()
                    .fill(theme.text)
                    .frame(width: 5, height: 5)
                    .position(actualEnd(in: proxy.size))
            }
        }
        .frame(height: Self.chartHeight)
    }

    /// Both lines share one scale, or the comparison they exist to make is
    /// meaningless. Never zero — a crew with no plan and no sessions still
    /// gets a chart with a floor rather than a division by nothing.
    private var ceiling: Double {
        max(CrewWeekMath.plannedSeries(week).last ?? 0,
            CrewWeekMath.actualSeries(week).max() ?? 0,
            1)
    }

    /// The dotted plan: eight points across the full width, Monday morning's
    /// nothing to Sunday night's whole plan.
    private func plannedPath(in size: CGSize) -> Path {
        let planned = CrewWeekMath.plannedSeries(week)
        var path = Path()
        for (index, value) in planned.enumerated() {
            let steps = CGFloat(max(planned.count - 1, 1))
            let point = CGPoint(x: size.width * CGFloat(index) / steps,
                                y: size.height * (1 - CGFloat(value / ceiling)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// The solid actual, Monday to today.
    private func actualPath(in size: CGSize) -> Path {
        let actual = CrewWeekMath.actualSeries(week)
        var path = Path()
        for index in actual.indices {
            let point = actualPoint(index, in: size)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// The filled dot: where "now" is on a week that has not finished.
    private func actualEnd(in size: CGSize) -> CGPoint {
        let actual = CrewWeekMath.actualSeries(week)
        return actualPoint(max(actual.count - 1, 0), in: size)
    }

    /// The actual line spans Monday…today, so its x is measured against the
    /// WEEK's span and never against its own point count — otherwise a
    /// Tuesday's two points would stretch across the whole chart and the crew
    /// would look a week ahead of itself.
    private func actualPoint(_ index: Int, in size: CGSize) -> CGPoint {
        let actual = CrewWeekMath.actualSeries(week)
        guard actual.indices.contains(index) else { return .zero }
        let span = CGFloat(CrewWeekMath.daysInWeek)
        // Two points means "a total, drawn straight": the second one belongs
        // on today's x, not on day one's.
        let x: CGFloat = actual.count == 2
            ? size.width * CGFloat(index) * CGFloat(CrewWeekMath.today(week) + 1) / span
            : size.width * CGFloat(index) / span
        return CGPoint(x: x,
                       y: size.height * (1 - CGFloat(actual[index] / ceiling)))
    }

    /// One chip per lifter, in the existing tag style — `Alex 2/3`, and
    /// `Mo 2/–` for a lifter who set no goal.
    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(week.lifters) { lifter in
                GSTag(text: CrewWeekMath.chip(lifter), style: .outline)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Check in

/// The gold Check In control, lifted out of the lobby's foot so the warm-up
/// screen presses the same button (plan task S9).
///
/// **GOLD'S SECOND JOB, ONCE** (design rule 2). Gold has exactly two: the
/// week-streak number, and "the window is open, act now". This is the second,
/// and it is the only gold anywhere in Phase A — which is also why it is one
/// component rather than two drawings: a second copy is a second chance for
/// one of them to stop being gold.
///
/// It renders three states and no fourth: checking in, waiting for the window
/// (with the time it opens), and open. The caller owns `canCheckIn`,
/// `checkInOpensAtText` and the tap, exactly as `LobbyView` computed them
/// before this moved.
struct SessionCheckInControl: View {
    /// HomeView's ready-state palette (`goldTop`/`goldInk`) — the fixed STATUS
    /// colour. The lip derives from the face, never a lighter tint.
    static let gold = Color.gsHex(0xF6C945)
    static let goldInk = Color.gsHex(0x261A02)

    let isCheckingIn: Bool
    let canCheckIn: Bool
    /// `"7:40 AM"` — empty when the session has no scheduled time, which is
    /// the fail-open case `canCheckIn` already answers true for.
    let opensAtText: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if isCheckingIn {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Self.goldInk)
                    Text("Checking in…")
                        .font(GSFont.bold(15, relativeTo: .body))
                } else if !canCheckIn {
                    Image(systemName: "clock")
                        .font(.system(size: 15))
                    Text("Check-in opens at \(opensAtText)")
                        .font(GSFont.bold(15, relativeTo: .body))
                } else {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 15))
                    Text("Check In")
                        .font(GSFont.bold(15, relativeTo: .body))
                }
                Spacer()
            }
            .foregroundStyle(Self.goldInk)
            .padding(.horizontal, 16)
            // 8.5 pt vertical: content + 17 + the 7 pt lip keeps the button's
            // exact footprint from before it was lifted.
            .padding(.vertical, 8.5)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gs3D(face: Self.gold, cornerRadius: GSMetrics.radiusSm))
        .disabled(isCheckingIn || !canCheckIn)
    }
}
