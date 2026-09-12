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
    /// Spec §3.2: in a crew, Coach speaks to each lifter privately, and a crew
    /// screen that shows a Coach line without saying so reads as a broadcast.
    static let onlyYouSeeThis = "Only you see this."
    /// The same two words `GSConsentCard` uses, so a suggestion answers the
    /// same way everywhere in the app.
    static let accept = GSConsentCopy.accept
    static let decline = GSConsentCopy.decline
    /// Coach's door (spec §3.6).
    static let talkToCoach = "Talk to Coach"
    static let talkToCoachDetail = "This session's focus · form questions · demo videos"
    /// The swap control on a plan row — flat furniture on a raised card.
    static let swap = "Swap"

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
    /// `GSInitialsAvatar` clips itself to `size * 0.28`; the empty tile
    /// matches so the two read as the same shape.
    private static let avatarRadius: CGFloat = 30 * 0.28

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
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(0.9)
            }
            .foregroundStyle(people.isEmpty ? theme.neutral500 : theme.neutral700)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if people.isEmpty {
                RoundedRectangle(cornerRadius: Self.avatarRadius)
                    .strokeBorder(theme.neutral400, lineWidth: 1)
                    .frame(width: Self.avatar, height: Self.avatar)
            } else {
                HStack(spacing: -8) {
                    ForEach(people) { person in
                        GSInitialsAvatar(name: person.name,
                                         avatarURL: person.avatarURL,
                                         size: Self.avatar)
                            .overlay(
                                RoundedRectangle(cornerRadius: Self.avatarRadius)
                                    .strokeBorder(theme.surface, lineWidth: 2)
                            )
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
/// A FIXED 28 pt row height, so four rows make four straight edges whether or
/// not a row carries a chip; and a 3 pt gutter reserved whether or not a row
/// is current, so the current row's mark cannot shift the names out of their
/// column.
struct SessionPlanCard: View {
    @Environment(\.gsTheme) private var theme

    let kicker: String
    /// Today's rung, above the rows: what the block asks of this session.
    let rungLine: String
    let rows: [SessionPlanRow]
    /// The leader can swap any row before Start (spec §3.1).
    var showsSwap: Bool = false
    /// What a `Swap` chip does. Nil is the same as `showsSwap: false`.
    var onSwap: ((SessionPlanRow) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GSSectionHeader(kicker)
            if !rungLine.isEmpty {
                Text(rungLine)
                    .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GSDivider()
            ForEach(rows) { row in
                SessionPlanRowView(row: row,
                                   showsSwap: showsSwap && onSwap != nil,
                                   onSwap: { onSwap?(row) })
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }
}

/// One plan row. Its own view rather than a method, because
/// `SessionPlanCardWithSuggestion` draws the same rows and two drawings of a
/// row is how two cards stop lining up.
private struct SessionPlanRowView: View {
    @Environment(\.gsTheme) private var theme

    let row: SessionPlanRow
    let showsSwap: Bool
    let onSwap: () -> Void

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

            if showsSwap { swapChip }
        }
        .frame(height: 28)
    }

    /// A FLAT capsule chip on the raised card — furniture inside a raised box
    /// stays flat (rule 1).
    private var swapChip: some View {
        Button(action: onSwap) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold))
                Text(SessionCopy.swap)
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
    /// Coach's line. Nil renders the card with no suggestion and no rule.
    var suggestion: String?
    var isPrivate: Bool = false
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            GSDivider()
            ForEach(rows) { row in
                SessionPlanRowView(row: row, showsSwap: false, onSwap: {})
            }
            if let suggestion {
                GSDivider().padding(.top, 3)
                CoachSuggestionBlock(line: suggestion,
                                     isPrivate: isPrivate,
                                     onAccept: onAccept,
                                     onDecline: onDecline)
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
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

// MARK: - Coach's suggestion

/// Coach's `CO` tile, the first-person line, the privacy note, and the two
/// raised pills — `SVSuggestionBody`'s composition.
///
/// **Accept / Not today**, the same two words `GSConsentCard` uses (plan task
/// S2), so a suggestion answers the same way everywhere in the app.
struct CoachSuggestionBlock: View {
    @Environment(\.gsTheme) private var theme

    let line: String
    /// Spec §3.2: in a crew Coach speaks to each lifter privately, and the
    /// frame has to say so or the crew reads it as a broadcast.
    var isPrivate: Bool = false
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachLine
            if isPrivate {
                Text(SessionCopy.onlyYouSeeThis)
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
            HStack(spacing: 8) {
                pill(SessionCopy.accept, action: onAccept)
                pill(SessionCopy.decline, action: onDecline)
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
                + Text(line)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
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

    let title: String
    let detail: String
    /// The line that says why this is not available — the crew's Coach thread
    /// is Pro, and this names whose it is waiting on.
    var note: String?
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
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
/// Ink is `theme.text`, **not** the inert `neutral700` of a gated control:
/// this one is live, and a secondary that reads as disabled would tell the
/// leader the only reachable control does nothing.
struct SecondaryStartButton: View {
    @Environment(\.gsTheme) private var theme

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

            Text(note)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .frame(maxWidth: .infinity, alignment: .center)
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

/// A STRIP at 22 pt, not a hero: the largest thing on the warm-up screen is
/// what you are about to lift.
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
                    .font(GSFont.bold(22, relativeTo: .title3))
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
