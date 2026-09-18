import SwiftUI

// MARK: - RoundPieces
//
// The parts the three live styles share (plan tasks S6, S7, S8). Reference
// frames: `round-wait-v2` (123), `round-skip-offer` (114) and
// `round-spotter-v3` (128) — the design round's renders, rebuilt as
// PRODUCTION views that take values.
//
// VALUE-IN, ALL OF THEM (constraint 11). Nothing here reads a repository, a
// clock or `AppState`: every piece takes what it prints. That is what lets
// the catalog render the real production view over `LiveFixtures` instead of
// a mockup, and it is why the elapsed rest arrives as an already-formatted
// string (`WarmUpScreen.elapsed`'s precedent) rather than as a `Date` the
// card would have to tick.
//
// ALIGNMENT IS A RULE (the second pass's own, from the design round's now-
// retired `Variations/` kit): every side-by-side arrangement reserves FIXED
// SLOTS, so two cards cannot disagree about a baseline because one of them
// carries an extra line.

// MARK: - The zone, as a word and as ink

/// Heart-rate zone display — the one exception to the colour rules, and the
/// word that goes with it (constraint 13 / design language §4a, owner
/// decision 17).
///
/// THE COLOUR NEVER TRAVELS ALONE. Wherever a heart rate is shown — the
/// recovery curve's endpoint (S6), the spotter's crew rows (S8), Together's
/// timeline (S9) — the zone colour is allowed AND the zone word accompanies
/// it, so the meaning never rests on colour alone.
///
/// `ink` is `GSHeartRatePill`'s own mapping, spelled here because the pill's
/// is private and these surfaces draw dots, bars and numbers rather than
/// pills. Both read `HeartRateZone`, so the two cannot disagree about which
/// zone a reading is in.
enum HeartRateZoneDisplay {

    /// `Z1`-`Z4`. A reader who cannot separate orange from red still gets the
    /// zone, and the word costs 22 points.
    static func word(_ zone: HeartRateZone) -> String {
        switch zone {
        case .warmup:   return "Z1"
        case .moderate: return "Z2"
        case .hard:     return "Z3"
        case .max:      return "Z4"
        }
    }

    /// The four-colour effort ramp, identical to `GSHeartRatePill.zoneColor`.
    static func ink(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .warmup:   return .blue
        case .moderate: return .green
        case .hard:     return .orange
        case .max:      return .red
        }
    }
}

// MARK: - The copy, and the laws behind it

/// Every string the round screens print that is not simply a name, and the
/// pure laws that build them (plan tasks S6, S7, S8).
///
/// Here rather than in a view body for the reason `RoundHold`'s constants are
/// in `RoundHold`: a sentence assembled inline in one screen is a sentence
/// that reads differently in the next one, and `RoundWaitCopyTests` asserts
/// these as strings.
enum RoundCopy {

    /// `PUSH CREW · ROUND 3` — the page's kicker.
    static func kicker(crew: String, round: Int) -> String {
        crew.isEmpty ? "ROUND \(round)" : "\(crew.uppercased()) · ROUND \(round)"
    }

    /// `"2:31"` — a duration, minutes and padded seconds. Negative reads
    /// `0:00`: nothing in this app has waited a negative amount of time.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }

    /// `"1:42"` — the rest clock. `WarmUpGate.elapsed(since:now:)`'s law,
    /// verbatim: nil and negative both read `0:00`, because a rest that has
    /// not started has not run backwards.
    static func elapsed(since startedAt: Date?, now: Date) -> String {
        guard let startedAt else { return "0:00" }
        return clock(now.timeIntervalSince(startedAt))
    }

    // MARK: - The hold (spec §9a, owner decision 11, plan task S7)

    /// `Sam's still resting — go ahead without them?`
    ///
    /// The spec writes "without him". The app knows no pronoun for anybody —
    /// `profiles` has no gender column and inventing one from a name is how
    /// software insults people — so the production string is THEM, and
    /// `RoundWaitCopyTests` pins it so a later edit cannot quietly guess.
    static func skipOffer(name: String) -> String {
        "\(name)'s still resting — go ahead without them?"
    }

    /// `Waited 2:31 — past the 2:24 the crew's own rest sets.`
    ///
    /// §9a's rule made legible: the threshold is not a policy number, it is
    /// this crew's own measured rest × 1.5 (floored at 90 s, capped at 180).
    /// Printing both figures is what stops the offer reading as the app
    /// deciding somebody is slow.
    static func skipWaited(waited: TimeInterval, threshold: TimeInterval) -> String {
        "Waited \(clock(waited)) — past the \(clock(threshold)) the crew's own rest sets."
    }

    /// What the skip costs the lifter: nothing. Their set stays in their plan
    /// and they rejoin at the top of the next round — which is already true
    /// of the data model, and the task's job is to keep it true.
    static let skipConsequence = "Nothing is recorded against them. They rejoin next round."

    /// The held lifter's own control (owner decision 11). Once per exercise.
    static let needAMinute = "I need a minute"

    /// The line under it, so the tap says exactly what happens (rule 9).
    static let needAMinuteDetail = "Adds a minute before the crew is offered a skip."

    // MARK: - Spotter mode (spec §1, owner decision 7, plan task S8)

    /// Why this screen is up. Owner decision 7: spotter mode is what a lifter
    /// does in the rounds their prescription has no set for.
    static let spotterNoSet = "Your plan has no set this round."

    /// The promise the mode exists to keep — "with the crew, not a solo
    /// recap".
    ///
    /// THE REFERENCE FRAME SAYS "until round 5" AND PRODUCTION DOES NOT.
    /// Which round a lifter rejoins on depends on how fast four other people
    /// get through their remaining sets, and `SessionLiveView`'s own
    /// (now-retired) `upcomingTurnHint` already refused to fabricate the
    /// same kind of number ("the proof's '~2 min' isn't backed by any
    /// duration data we track"). A wrong round in the copy is worse than no
    /// round.
    static let spotterWithTheCrew = "You're with the crew — not in a recap on your own."

    /// The crew's live readings. Owner decision 13 shares heart rate by
    /// default, and the card says so out loud rather than leaving the lifter
    /// to discover it.
    static let crewRightNow = "THE CREW, RIGHT NOW"
    static let sharedByDefault = "SHARED BY DEFAULT"

    /// `2 STILL TO GO` — how much of this round is left. A kicker, so caps.
    static func stillToGo(_ count: Int) -> String {
        "\(count) STILL TO GO"
    }

    /// The spotter's one act, and the screen's one accent.
    static let cheer = "Cheer"

    /// What CHEER puts on the wire — the applause pill, on the reaction
    /// channel the strip already uses. Cheering IS reacting, loudly; a
    /// separate kind for the same act would be two ways to clap.
    static let cheerEmoji = "👏"

    // MARK: - Together (spec §3.3, owner decisions 1 and 13, plan task S9)

    /// `INTERVAL 6 OF 12` — the clock's kicker.
    static func intervalKicker(index: Int, count: Int) -> String {
        "INTERVAL \(index + 1) OF \(count)"
    }

    /// `Next: Z2 · 3 min`, or the honest end of the run.
    static func nextInterval(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "Last interval" }
        return "Next: \(detail)"
    }

    /// Together's whole point, said out loud so nobody waits for a turn that
    /// is never coming.
    static let togetherNoTurn = "Everyone runs this clock. There is no turn."

    /// The crew's card on the Together screen.
    static let crewOneTimeline = "THE CREW · ONE TIMELINE"

    /// The foot's shipped End control — the same confirmation the header's X
    /// raises.
    static let endSession = "End"

    /// What "I need a minute" puts on the wire.
    ///
    /// The EXISTING reaction channel (plan task S7: "no new channel"), so
    /// this is a reaction payload rather than a new broadcast kind. An
    /// hourglass, because a client that has not been taught the marker floats
    /// a harmless glyph rather than raw text — and because the crew seeing an
    /// hourglass is, in the moment, the message. It is not one of the four
    /// pills `ReactionStrip` offers, so no tap can send it by accident.
    static let minuteMarker = "⏳"

    // MARK: - Freestyle (spec §3.3, owner decision 4, plan task S10)

    /// The page's own headline. "Freestyle" is the style's proper noun (the
    /// lobby card's word, `SessionStyleCopy.of(.freestyle).title`); this page
    /// says what living it actually feels like.
    static let freestyleTitle = "Own pace"

    static let freestyleRailKicker = "THE CREW · SETS DONE"

    /// `OF 18` — the rail's trailing count against the routine's own total.
    static func freestyleOfTotal(_ total: Int) -> String { "OF \(total)" }

    static let freestyleYourRest = "YOUR REST"

    /// The stretched-rest suggestion's kicker.
    static let freestyleStretchKicker = "COACH IS STRETCHING YOUR REST"

    /// `You're two sets up — Coach is stretching your rest to keep the crew
    /// together.` The exact sentence the plan quotes, for the exact count the
    /// fixture carries (2) — `spelled(_:)` keeps small counts in words the
    /// way the sentence reads, and falls back to a digit past ten rather than
    /// inventing an English word for it.
    static func freestyleStretchSentence(setsAhead: Int) -> String {
        "You're \(spelled(setsAhead)) sets up — Coach is stretching your rest to keep the crew together."
    }

    private static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five",
                     "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }

    static let freestyleAccessoryKicker = "COACH SUGGESTS"

    /// `While they catch up — Face pulls, 3 × 12?` THE PLAN'S OWN ROW, never
    /// an invented one — `FreestylePace.accessorySuggestion` only ever
    /// answers with an isolation row that is actually on the routine, and
    /// this is the whole of what it says about it: a name and the
    /// prescription already printed, nothing this app does not know.
    static func freestyleAccessorySentence(name: String, prescription: String) -> String {
        "While they catch up — \(name), \(prescription)?"
    }

    /// A lifter behind sees the wait stated, with nothing to accept — the
    /// suggestion is for whoever is ahead, and a lifter behind has nothing to
    /// answer for.
    static let freestyleBehindLine = "The crew is still resting. Take the time you need."

    // MARK: - The round wait's own lines

    /// `WAITING ON SAM AND LEE` — the foot's gated control.
    ///
    /// A kicker, so caps (rule 3). The Oxford-free join is the app's: two
    /// names take `AND`, three or more take commas and a final `AND`.
    static func waitingOn(_ names: [String]) -> String {
        let cleaned = names.filter { !$0.isEmpty }.map { $0.uppercased() }
        switch cleaned.count {
        case 0:  return "WAITING ON THE CREW"
        case 1:  return "WAITING ON \(cleaned[0])"
        case 2:  return "WAITING ON \(cleaned[0]) AND \(cleaned[1])"
        default:
            let head = cleaned.dropLast().joined(separator: ", ")
            return "WAITING ON \(head) AND \(cleaned[cleaned.count - 1])"
        }
    }

    /// `Set 3 of 4 · Back squat 225 × 5` — what the lifter is resting FOR
    /// (spec §2's next prescription).
    ///
    /// Every part is optional because every part can genuinely be missing: a
    /// routine with no target sets, an exercise the catalog has not resolved,
    /// a prescription with no weight. What is absent is left out rather than
    /// dashed — a dash inside a sentence reads as a broken value.
    static func nextPrescription(setNumber: Int,
                                 targetSets: Int?,
                                 exercise: String?,
                                 prescription: String?) -> String {
        var parts: [String] = []
        if let targetSets {
            parts.append("Set \(setNumber) of \(targetSets)")
        } else {
            parts.append("Set \(setNumber)")
        }
        let movement = [exercise, prescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !movement.isEmpty { parts.append(movement) }
        return parts.joined(separator: " · ")
    }

    /// Spec §2's "is the plan still achievable" check, from the only two
    /// numbers the app actually has: what this lifter last moved on this
    /// movement, and what the routine prescribes.
    ///
    /// A STATEMENT, NEVER A VERDICT. The reference frame's copy ("Set 2 moved
    /// at 225. The plan still holds.") reads as a judgment; production can
    /// only honestly say what happened and what is on the plan, so the third
    /// branch names the gap instead of predicting the outcome.
    static func achievability(lastMoved: String?,
                              target: String?,
                              isUnderTarget: Bool) -> String {
        guard let lastMoved, !lastMoved.isEmpty else {
            return "Nothing logged on this movement yet."
        }
        guard let target, !target.isEmpty, isUnderTarget else {
            return "Last set moved at \(lastMoved). The plan still holds."
        }
        return "Last set moved at \(lastMoved) — under the \(target) on the plan."
    }
}

// MARK: - The page

/// The scaffold the three round screens share: a kicker and a title, a
/// scrolling body, and a PINNED foot.
///
/// The design round's own scroll-screen scaffold (retired, `Features/
/// Sessions/Variations/`), brought across — same geometry, same reasoning:
/// these screens carry more than a fixed page can hold, and a fixed page
/// that overflows CLIPS its foot, which would hide the one control the
/// screen exists to offer.
struct RoundPage<Content: View, Foot: View>: View {
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

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 10) {
                foot
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
    }
}

// MARK: - The two voice notices

/// The degraded banner and the first-run coach mark, as ONE value so a screen
/// carries one parameter instead of four (fix round 1 / F2, ruling R-B12).
///
/// Not `Equatable` — it holds the two closures — which is fine: no screen
/// diffs on it.
struct VoiceFoot {
    var isUnavailable: Bool = false
    var showsCoachMark: Bool = false
    var onRetry: () -> Void = {}
    var onDismissCoachMark: () -> Void = {}
}

/// Both notices, drawn ABOVE the dock, wherever the dock is.
///
/// One spelling for two feet: `SessionLiveView`'s pinned `turnChrome` and the
/// round screens' own pinned foot both render this, so the mark cannot teach
/// the dock in one place and not the other — the exact failure the strip
/// caused when `legacyBottomChrome` took the only mount with it.
struct VoiceNotices: View {
    let foot: VoiceFoot

    /// No wrapper stack: with neither notice showing this must resolve to
    /// `EmptyView`, so a foot that stacks its children with spacing does not
    /// reserve a gap for two things that are not there.
    @ViewBuilder
    var body: some View {
        if foot.isUnavailable {
            GSVoiceUnavailableBanner(retry: foot.onRetry)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        if foot.showsCoachMark {
            GSVoiceCoachMark(onDismiss: foot.onDismissCoachMark)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
    }
}

// MARK: - The reaction strip

/// The four pills, value-in (fix round 1 / F3).
///
/// Verbatim the strip the soundboard dock used to carry. Plan task S4 lifted
/// it out of the dock and left it WITH NO CALL SITE — correctly, since adding
/// a strip to the my-turn page's approved chrome is a composition change and
/// not a deletion's cost — which meant a crewmate could not react at all from
/// the live view. THE STRIP RIDES WITH THE DOCK (fix round 5, final review
/// finding 6): every page that mounts a `PTTDockRow` mounts this above it —
/// the round wait's and spotter's feet, `SessionLiveView.turnChrome`
/// (Rounds-my-turn and Freestyle) and `TogetherClockView`'s foot, five of
/// five — because riding with the dock is exactly what the dock it was cut
/// out of used to guarantee.
///
/// The emoji ARE content here, which is the one exception design rule 9's
/// no-decorative-emoji clause names.
struct ReactionStrip: View {
    @Environment(\.gsTheme) private var theme

    let emojis: [String]
    var onTap: (String) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        onTap(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 13))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                                .strokeBorder(theme.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - The gated control

/// The foot's soft gate: `WAITING ON SAM AND LEE`.
///
/// A RAISED NEUTRAL FACE, never accent (design rule 2). The next act belongs
/// to the crew, not to the reader, so the screen does not offer a button that
/// looks like theirs to press.
struct GatedControl: View {
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

// MARK: - The skip offer

/// The three lines the crew is offered when one lifter is past the threshold
/// (plan task S7).
struct SkipOffer: Equatable {
    /// The held lifter, first name — the crew's own word for them.
    let name: String
    /// How long the crew has waited, in seconds. A NUMBER, not a string:
    /// `RoundCopy.skipWaited` is the one place it becomes `2:31`, and that
    /// law is what the copy test asserts.
    let waited: TimeInterval
    /// The threshold they are past, in seconds — `RoundHold`'s own answer for
    /// this crew, never a literal.
    let threshold: TimeInterval
}

/// ONE QUIET LINE, NEVER A DIALOG (spec §9a). Nothing happens on its own.
///
/// INK on a `surface` strip with a `neutral700` hairline — an invitation, not
/// a filled slab, which would read as the crew's next step rather than as an
/// option.
///
/// NO ACCENT (fix round 5, final review finding 7; design rule 2). This line
/// used to paint an accent hairline AND accent ink, which made it the round
/// wait's SECOND accent-bearing element beside `StationCard`'s turn ring —
/// and the old justification, that at the threshold the ring and this line
/// are the same fact, is false with two racks: the global turn can sit on a
/// lifter this line does not name, which is exactly the configuration plan
/// task S3 exists to create. The ring keeps the accent because the turn is
/// the round wait's primary; the skip is an option about it, drawn in ink,
/// and it still leads with the glyph and the largest type in the strip so
/// nothing about its weight on the page changes.
///
/// ALWAYS TAPPABLE, BY ANY CREWMATE (ruling R-B13, fix-forward
/// `20260913000107`, applied live). Spec §9a's own rule, finally true:
/// `SessionRepository.advanceRound`'s `force` parameter bypasses
/// `public.advance_round`'s close predicate once the round is genuinely
/// old enough (the server's own floor, not a client-side gate), so the tap
/// closes the round for whoever presses it — no organizer-only button, no
/// note-for-everyone-else fallback.
struct SkipOfferLine: View {
    @Environment(\.gsTheme) private var theme

    let offer: SkipOffer
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            lines
                .roundStrip()
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(theme.neutral700, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Moves the crew on without them")
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "forward.end")
                    .font(.system(size: 12, weight: .bold))
                Text(RoundCopy.skipOffer(name: offer.name))
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.text)

            Text(RoundCopy.skipWaited(waited: offer.waited, threshold: offer.threshold))
                .font(GSFont.body(11.5, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
            Text(RoundCopy.skipConsequence)
                .font(GSFont.body(11.5, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
    }
}

// MARK: - The strip

/// The chrome a strip wears on these screens: `theme.surface`, 14 pt — a
/// strip, not a card (rule 1). `SessionPieces`' own `sessionStrip()` is
/// file-private to that file; this is the same five values, and the two are
/// asserted identical by eye rather than by a shared symbol because making
/// the Phase A modifier internal is a change to a frozen file that buys one
/// call site.
struct RoundStripModifier: ViewModifier {
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
    /// Internal, not file-private: spotter mode (plan task S8) is a second
    /// file that needs the same five values.
    func roundStrip() -> some View { modifier(RoundStripModifier()) }
}

// MARK: - The station card

/// One station — RACK A, RACK B — built from FIXED SLOTS so that two of them
/// side by side agree on every edge the eye checks (plan task S6, reference
/// `round-wait-v2`'s own station card, design round, now retired).
///
/// **The alignment argument, kept.** A card that sizes itself to its content
/// is a card whose height depends on whether one of its lifters happens to
/// carry a personal scale-down line. So the title row is `titleHeight`
/// whatever the rack is called, every lifter column is `columnHeight` whether
/// or not there is a substitution under the name, and the content is
/// `contentHeight` however many people are on it. Two cards built from
/// constants cannot disagree.
///
/// ACCENT: the ring on the lifter whose turn it is — the round wait's one
/// accent act (rule 2). The logged tick is `Color.gsSuccess`, which means
/// done, and nothing else on this card spends a colour.
struct StationCard: View {
    @Environment(\.gsTheme) private var theme

    /// One lifter's column.
    struct Lifter: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// "You" rather than your own name: the crew reads the card to find
        /// themselves on it.
        let isYou: Bool
        /// A non-penalty set logged for the current exercise.
        let hasLogged: Bool
        /// Spec §3.4 mode 2 — the quiet personal scale-down, visible only
        /// where the crew already looks. `nil` for everyone lifting the
        /// crew's own prescription; the LINE IS RESERVED either way.
        let scaleDown: String?
    }

    /// One station. `Identifiable` by its name, which
    /// `StationSplit.name(_:)` guarantees is unique within an assignment.
    struct Model: Identifiable, Equatable {
        let name: String
        let lifters: [Lifter]
        /// The lifter whose turn it is, if they are on THIS station.
        let liftingID: UUID?

        var id: String { name }
    }

    let model: Model

    /// The three constants two cards must share to line up.
    private static let titleHeight: CGFloat = 14
    private static let columnHeight: CGFloat = 70
    private static let contentHeight: CGFloat = titleHeight + 10 + columnHeight
    private static let columnWidth: CGFloat = 52
    private static let avatarSize: CGFloat = 36

    private var loggedLine: String {
        let logged = model.lifters.reduce(0) { $0 + ($1.hasLogged ? 1 : 0) }
        return "\(logged)/\(model.lifters.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                GSSectionHeader(model.name)
                Spacer(minLength: 0)
                Text(loggedLine)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
                    .fixedSize()
            }
            .frame(height: Self.titleHeight)

            HStack(alignment: .top, spacing: 0) {
                ForEach(model.lifters) { lifter in
                    column(lifter)
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.columnHeight, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.contentHeight + 24, alignment: .top)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)
    }

    /// Avatar, name, and a RESERVED line for the personal scale-down whether
    /// or not this lifter has one — what keeps two racks' avatar rows on one
    /// baseline.
    private func column(_ lifter: Lifter) -> some View {
        VStack(spacing: 4) {
            GSInitialsAvatar(name: lifter.name, size: Self.avatarSize)
                .overlay(alignment: .bottomTrailing) { tick(lifter) }
                .overlay(ring(lifter))
            Text(lifter.isYou ? "You" : SessionCopy.firstName(lifter.name))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 13)
            Text(lifter.scaleDown ?? " ")
                .font(GSFont.body(10, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)
        }
        .frame(width: Self.columnWidth, height: Self.columnHeight, alignment: .top)
    }

    @ViewBuilder
    private func tick(_ lifter: Lifter) -> some View {
        if lifter.hasLogged {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.gsSuccess)
                .background(Circle().fill(theme.bg).frame(width: 12, height: 12))
        }
    }

    @ViewBuilder
    private func ring(_ lifter: Lifter) -> some View {
        if lifter.id == model.liftingID {
            RoundedRectangle(cornerRadius: Self.avatarSize * 0.28)
                .strokeBorder(theme.accent, lineWidth: 2)
        }
    }
}

// MARK: - The turn strip

/// NOW / NEXT / 3RD / 4TH — who is lifting and who is behind them.
///
/// Moved out of `SessionLiveView` (plan task S8), where it had had no call
/// site since the strip took the page that mounted it, and made value-in so
/// spotter mode can render it. The drawing is unchanged.
struct TurnStrip: View {
    @Environment(\.gsTheme) private var theme

    struct Tile: Identifiable, Equatable {
        let id: UUID
        /// `NOW`, `NEXT`, `3RD` …
        let label: String
        /// "You" rather than your own name.
        let name: String
        let isNow: Bool
        /// The speaking ring — `VoiceRoomService.speakingParticipantIDs`,
        /// resolved by the caller because only it holds the identity map.
        var isSpeaking: Bool = false
        /// SPEC §3.4 MODE 2, WHERE THE CREW ALREADY LOOKS (plan task S2).
        /// The replacement exercise this lifter has quietly scaled to for the
        /// exercise the crew is on — `SessionLiveView.selfScales`, the same
        /// lookup `stationLifter` makes for the station card.
        ///
        /// Nil draws NOTHING, not a blank line: a tile without a scale-down
        /// keeps its current two-line height, so the strip's baselines do not
        /// move on frames 137-139 (constraint 14). Defaulted, so every
        /// existing call site compiles unchanged.
        var doing: String? = nil
    }

    let tiles: [Tile]

    /// THE CURRENT TILE'S FILL, independent of everything else. A screen that
    /// has spent its one accent elsewhere — spotter mode's CHEER — marks NOW
    /// with the raised neutral face instead (rule 2).
    var accentsCurrent: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("ROTATION")
            HStack(spacing: 6) {
                ForEach(tiles) { tile in
                    self.tile(tile)
                }
            }
        }
    }

    private func tile(_ tile: Tile) -> some View {
        let filled = tile.isNow && accentsCurrent
        return VStack(spacing: 4) {
            Text(tile.label)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(filled ? theme.bg.opacity(0.85) : theme.neutral500)
            Text(tile.name)
                .font(GSFont.bold(13, relativeTo: .body))
                .foregroundStyle(filled ? theme.bg : theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // Quiet, and only when there is one (plan task S2): no badge, no
            // banner, no colour — the name of the lift they are actually on,
            // under the name of the lifter.
            if let doing = tile.doing {
                Text(doing)
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(filled ? theme.bg.opacity(0.85) : theme.neutral500)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(filled ? theme.accent : theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(
            tile.isSpeaking ? theme.accent700
                : (tile.isNow && !accentsCurrent ? theme.neutral500
                   : (filled ? Color.clear : theme.divider)),
            lineWidth: tile.isSpeaking ? 2 : 1))
    }
}

// MARK: - The crew's heart rates

/// `THE CREW, RIGHT NOW` — the card that turns spotter mode from a waiting
/// room into a job (plan task S8, reference `round-spotter-v3`).
///
/// The reason to be at the rack is that you can see Dana is at 158 and Lee
/// has come down to 121. Owner decision 13 already shares heart rate by
/// default; this is the first screen that uses it for anybody other than the
/// lifter it belongs to, which is why the card says SHARED BY DEFAULT out
/// loud instead of leaving it to be discovered.
///
/// COLOUR AND WORD TOGETHER (§4a, owner decision 17). `GSHeartRatePill`
/// already tints by zone; the WORD beside it is what this card adds, so the
/// meaning never rests on colour alone. Who is LIFTING is marked by WEIGHT,
/// not by colour — the screen's accent is CHEER.
///
/// A STALE READING IS AN EM DASH, never a last-known number: the caller's
/// `heartRateFor(_:)` gate has already turned it into `nil`, and a heart rate
/// that stopped arriving is not a heart rate.
struct CrewHeartRatesCard: View {
    @Environment(\.gsTheme) private var theme

    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// Marked by weight, not colour.
        let isLifting: Bool
        /// Nil when the reading is stale or was never shared.
        let bpm: Int?
        let zone: HeartRateZone?
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                GSSectionHeader(RoundCopy.crewRightNow)
                Spacer(minLength: 8)
                Text(RoundCopy.sharedByDefault)
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral500)
                    .fixedSize()
            }
            ForEach(rows) { row in
                self.row(row)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private func row(_ row: Row) -> some View {
        HStack(spacing: 10) {
            Text(row.isLifting ? "\(row.name) · lifting" : row.name)
                .font(row.isLifting ? GSFont.bold(12.5, relativeTo: .caption)
                                    : GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(row.isLifting ? theme.text : theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            reading(row)
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func reading(_ row: Row) -> some View {
        if let bpm = row.bpm {
            GSHeartRatePill(bpm: bpm, zone: row.zone)
            Text(row.zone.map { HeartRateZoneDisplay.word($0) } ?? "—")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(theme.neutral700)
                .frame(width: 22, alignment: .trailing)
        } else {
            Text("—")
                .font(GSFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
            Text(" ")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .frame(width: 22, alignment: .trailing)
        }
    }
}

// MARK: - A door

/// A small raised tile with a glyph and two words (rule 4). The screen's one
/// primary act paints its face accent and its ink `theme.bg`, the way
/// `GSPrimaryButtonStyle` does.
struct RoundDoor: View {
    @Environment(\.gsTheme) private var theme

    let glyph: String
    let title: String
    var isPrimary: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
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
                                    face: isPrimary ? theme.accent : nil))
    }
}

// MARK: - The live log control

/// The inline "LOG SET & PASS" CTA — `SessionLiveView`'s `turnChrome` drew
/// this verbatim before ruling R-B17 (fix round 3 / F6): Together mounts
/// the SAME button in its own foot, above the dock, because
/// `logControlIsMine` (plan task S5) reads true for every participant in
/// `.together` — there is no turn to gate it on, and before this fix that
/// left Together with no way to log a set at all (`bottomChrome` never
/// renders `turnChrome` for `.together`). Lifted here, rather than
/// duplicated, so the two mounts cannot draw two different buttons.
struct LogControlButton: View {
    @Environment(\.gsTheme) private var theme

    let title: String
    /// The small readback line under the title. Absent while `isLoggingSet`
    /// — the original button showed `LOGGING…` alone, no second line.
    var readback: String? = nil
    var isFailed: Bool = false
    var isDisabled: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isFailed {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(theme.text, lineWidth: 1.5)
                }
                VStack(spacing: 2) {
                    Text(title)
                        .font(GSFont.bold(17, relativeTo: .body))
                        .tracking(0.9)
                    if let readback {
                        Text(readback)
                            .font(GSFont.bold(11, relativeTo: .caption2).monospacedDigit())
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(isFailed ? theme.text : theme.bg)
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isFailed ? theme.text : theme.bg)
                        .padding(.trailing, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 57)
        }
        .buttonStyle(.gs3D(face: isFailed ? theme.raised3DFace : theme.accent,
                           lip: isFailed ? theme.raised3DLip : nil,
                           cornerRadius: 16))
        .disabled(isDisabled)
    }
}

/// The values `LogControlButton` needs, bundled the way `VoiceFoot` bundles
/// the two voice notices (fix round 1 / F2's own precedent) — Together's
/// foot takes one parameter instead of four.
struct LogControlFoot {
    var title: String = "LOG SET & PASS"
    var readback: String? = nil
    var isFailed: Bool = false
    var isDisabled: Bool = false
    var onTap: () -> Void = {}
}

/// Whose act the log control is — `SessionLiveView.logControlIsMine`'s own
/// rule (plan task S5), pulled out as a pure function (finding 1, ruling
/// R-B21) so it can be unit tested without standing up a live view. Rounds
/// is a rotation: the entry belongs to whoever holds the turn. Freestyle and
/// Together have no turn at all (spec §3.3) — the entry is EVERYONE'S,
/// ALWAYS, never gated on who currently holds `currentTurnUserID`. Every
/// prefill call site and the log foot's own `isDisabled` read this one
/// answer, so the entry that fills the card and the button that logs it can
/// never disagree about whose turn it is.
enum LogControlGate {
    static func isMine(style: SessionStyle, isMyTurn: Bool) -> Bool {
        style == .rounds ? isMyTurn : true
    }
}

/// WHAT RUNS AFTER A SET IS PERSISTED, BY STYLE (ruling R-B22) — the second
/// half of `LogControlGate`'s law, pulled out for the same reason: the log
/// path's style rule is a pure question and belongs where it can be tested
/// without a live view.
///
/// `.rounds` is a rotation over a round: the set hands the turn on
/// (`advance_turn`) and then offers to close the round (`advance_round`,
/// never forced — the server closes it only once every present lifter has
/// logged, and returns the current round unchanged otherwise). Order matters:
/// the turn moves first, so the round that closes behind it already points at
/// the next lifter.
///
/// `.together` and `.freestyle` have NO turns and NO rounds (spec §3.3), so
/// they run NEITHER. That is not an optimisation — `advance_turn` is
/// current-lifter-or-organizer gated (`20260801000001`) and raises P0001
/// `'not your turn'` for everyone else, which is exactly what made every
/// non-turn-holder's perfectly good set report failure (final review,
/// finding 1). In those two styles the insert IS the whole transaction.
enum LogFollowUp {
    /// One server call, named rather than spelled, so the decision below is a
    /// value a test can read.
    enum Call: Equatable {
        case advanceTurn
        case advanceRound
    }

    /// In call order. Empty means the persisted set is the end of it.
    static func calls(for style: SessionStyle) -> [Call] {
        style == .rounds ? [.advanceTurn, .advanceRound] : []
    }
}

/// WHEN THE CURRENT ROUND OPENED (ruling R-B23) — the client's mirror of the
/// server's own window, `COALESCE(round_started_at, lifting_started_at,
/// '-infinity')` (`public.advance_round`, fix-forward `20260913000105`).
///
/// `sessions.round_started_at` is NULL until the FIRST round closes, and the
/// round-1 window is not "whatever this lifter has done today" — it opens
/// when the crew started lifting, which is precisely why `000105` exists: a
/// warm-up set must not count toward the first round. Reading
/// `lifting_started_at` second keeps the round-1 answer a FALLBACK to the
/// server's own rule rather than a second rule of the client's own invention.
///
/// Both values arrive on the `sessions` UPDATE the realtime channel already
/// carries (`SessionLiveService.onSessionChange` → `liveSession = updated`),
/// so every caller reads the live server round, never a cached one.
enum RoundWindow {
    static func openedAt(roundStartedAt: Date?, liftingStartedAt: Date?) -> Date? {
        roundStartedAt ?? liftingStartedAt
    }
}

// MARK: - The rest card

/// What the resting lifter is told (spec §2): how long they have been
/// resting, whether their heart is still falling, what is next, and whether
/// the plan still holds.
struct RestModel: Equatable {
    /// Already formatted — `RoundCopy.elapsed(since:now:)`. A VALUE, so this
    /// card owns no clock and a catalog frame is deterministic
    /// (`WarmUpScreen.elapsed`'s precedent).
    let elapsed: String
    /// `RecoveryBuffer.sparkline(barCount:)` — normalized 0...1, oldest
    /// first. Empty (fewer than two samples) draws no curve at all rather
    /// than a flat line that would claim a recovery nobody measured.
    let curve: [Double]
    /// The newest reading. `nil` when it is stale — `heartRateFor(_:)`'s
    /// 15 s freshness gate — and a stale reading renders as an em dash,
    /// never as a last-known number.
    let bpm: Int?
    let zone: HeartRateZone?
    let nextPrescription: String
    let achievability: String
}

/// The elapsed clock and the recovery curve on ONE row — the clock in a
/// FIXED 96 pt column so the curve's left edge lands in the same place on
/// every render — then the rule, then spec §2's next prescription and
/// achievability line.
///
/// The curve is `RecoveryBuffer.sparkline(barCount:)` over the samples the
/// watch bridge already publishes: NO NEW STORE (spec §6). Its endpoint
/// carries the zone colour and the zone word together (§4a).
struct RestRecoveryCard: View {
    @Environment(\.gsTheme) private var theme

    let model: RestModel

    private static let clockWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                clock
                    .frame(width: Self.clockWidth, alignment: .leading)
                recovery
            }
            GSDivider()
            VStack(alignment: .leading, spacing: 5) {
                GSSectionHeader("NEXT")
                Text(model.nextPrescription)
                    .font(GSFont.bold(15, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text(model.achievability)
                    .font(GSFont.body(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 2) {
            GSSectionHeader("ELAPSED REST")
            Text(model.elapsed)
                .font(GSFont.bold(38, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 6) {
            GSSectionHeader("RECOVERY")
            HStack(alignment: .bottom, spacing: 8) {
                RecoveryCurve(values: model.curve, endpointInk: endpointInk)
                readout
            }
            .frame(height: 40)
            Text("over \(model.elapsed) of rest")
                .font(GSFont.body(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
    }

    /// The zone's ink, on the number and on the curve's endpoint dot — and
    /// never without the word beside it (§4a). No reading, no colour.
    private var endpointInk: Color {
        guard let zone = model.zone else { return theme.text }
        return HeartRateZoneDisplay.ink(zone)
    }

    private var readout: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(model.bpm.map { "\($0)" } ?? "—")
                .font(GSFont.bold(17, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(model.bpm == nil ? theme.neutral500 : endpointInk)
            Text(zoneCaption)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
        }
        .fixedSize()
    }

    /// `BPM · Z3`, or `BPM` alone when no zone arrived with the reading.
    private var zoneCaption: String {
        guard let zone = model.zone, model.bpm != nil else { return "BPM" }
        return "BPM · \(HeartRateZoneDisplay.word(zone))"
    }
}

/// The recovery as a SHAPE. Two numbers with an arrow between them say where
/// the heart started and stopped; they do not say whether it is still
/// falling, which is the only question a lifter asks at 1:42 of rest.
///
/// Takes values already normalized to 0...1 by `RecoveryBuffer.sparkline`,
/// oldest first, so this view does no arithmetic on heart rates and the
/// bucketing is unit-tested where it lives.
struct RecoveryCurve: View {
    @Environment(\.gsTheme) private var theme

    let values: [Double]
    let endpointInk: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                path(width: proxy.size.width, height: proxy.size.height)
                    .stroke(theme.neutral700,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(endpointInk)
                    .frame(width: 6, height: 6)
                    .offset(x: proxy.size.width - 3,
                            y: point(index: values.count - 1, height: proxy.size.height) - 3)
                    .opacity(values.count > 1 ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// y measured from the TOP, so the highest reading sits highest.
    private func point(index: Int, height: CGFloat) -> CGFloat {
        guard values.indices.contains(index) else { return height }
        let share = CGFloat(min(max(values[index], 0), 1))
        return height - (height * share)
    }

    private func path(width: CGFloat, height: CGFloat) -> Path {
        Path { p in
            guard values.count > 1 else { return }
            let step = width / CGFloat(values.count - 1)
            for index in values.indices {
                let spot = CGPoint(x: step * CGFloat(index),
                                   y: point(index: index, height: height))
                if index == 0 {
                    p.move(to: spot)
                } else {
                    p.addLine(to: spot)
                }
            }
        }
    }
}
