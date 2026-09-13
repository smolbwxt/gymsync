#if DEBUG
import SwiftUI

// MARK: - The session design round, second pass — shared kit
//
// The owner reviewed all fourteen round-1 renders and picked: the lobby's
// arrival track (variation a), the warm-up screen as rendered, the round
// wait's station cards (variation b), and the skip offer, Freestyle,
// Together, the swap card and the pump card as they stand. This pass adds
// SEVEN ids beside them — every round-1 id is frozen, because the owner has
// approved those frames and a moved pixel in one of them is a moved decision.
//
// The round-1 kit's rules all still hold (see `SessionVariationKit.swift`):
// catalog-only, one world, one accent act per screen, no gold, nothing
// minted, no clock and no network. Three rules are ADDED by this pass:
//
//   * **ALIGNMENT IS A RULE.** Edges and baselines that should line up, do.
//     The owner saw the Rack A / Rack B cards sitting at different heights
//     with their titles and avatar rows off by a few points, because each
//     card sized itself to its own content and one of them carried an extra
//     line. Every side-by-side or stacked-column arrangement in this pass
//     therefore reserves FIXED SLOTS — a name row is a name row's height
//     whether or not the person under it has a substitution — so alignment
//     is a property of the layout rather than a coincidence of the fixture.
//   * ~~**NO ZONE COLOUR ON A HEART RATE.**~~ **REVERSED BY THE OWNER, third
//     pass.** This pass proposed neutral BPM ink with the zone as a word
//     (`Z4`), on the reading that the language reserves red and gold. The
//     owner's ruling: **heart-rate zone colours STAY — an explicit exception
//     to the colour rules**, which is what design language rule 2 already
//     said in its own heart-rate clause ("like plate colours, this is data
//     colour, not accent, and is exempt"). So `together-clock` (v1, frame
//     117) stands and `together-clock-v2` (126) is dropped conceptually —
//     its id and capture stay so the pair can still be looked at, and the
//     plan cites v1. `round-spotter-v3` (128) is `-v2` with the colours put
//     back. `SVZoneWord` survives the reversal and is kept BESIDE the
//     colour: a word a colour-blind reader can read is worth its 22 points
//     whatever the ink is doing.
//   * **CHECKED IN IS READY.** The round-1 lobby carried two signals — an
//     arrival stage and a separate readiness tick — and the owner removed
//     the second: the READY TO START roster is redundant. So the v2 lobby
//     counts one thing, the CHECKED IN column, and Start's caption says so.
//     This also settles the round-1 fixture's own inconsistency (the note on
//     `SVLifter.isReady`): with one signal there is nothing to reconcile.
//
// The v2 pieces live here rather than in `SessionVariationKit.swift` so that
// file stays exactly as the approved frames rendered it, apart from one
// additive defaulted field (`SVLifter.energy`).

// MARK: - Vocabulary

/// The heart-rate zone as a WORD, for the owner's ruling above. Same source
/// of truth as `GSHeartRatePill`'s tint (`HeartRateZone.zone(bpm:)`), so a
/// number that reads Z4 here is the number the pill would paint red.
enum SVZoneWord {
    static func of(_ bpm: Int) -> String {
        switch HeartRateZone.zone(bpm: bpm) {
        case .warmup:   return "Z1"
        case .moderate: return "Z2"
        case .hard:     return "Z3"
        case .max:      return "Z4"
        }
    }
}

/// One line of a routine: what it is, what is prescribed, and — where a
/// screen is mid-session — how far into it the crew is.
struct SVPlanRow: Identifiable {
    let id: Int
    let name: String
    let prescription: String
    var setsDone: Int = 0
    var sets: Int = 0
    /// The exercise the session is on right now. Exactly one row sets it.
    var isCurrent: Bool = false
}

// MARK: - The second pass's world
//
// The same crew, block and cast as round 1 — a difference between a v1 frame
// and its v2 is the composition, never a different session.

enum SVFixturesV2 {

    // MARK: Lobby (frames 120-121, retired — group-session Phase A plan,
    // task S11). `crewPlan` and `crewRungLine` outlived the two frames:
    // `round-wait-v2` (`RoundVariationsV2.swift`) reuses both.

    /// The WHOLE session, not a one-line rung. Four exercises is what a leg
    /// day is; a lobby that shows one of them is asking the crew to buy into
    /// a quarter of the plan.
    static let crewPlan: [SVPlanRow] = [
        SVPlanRow(id: 1, name: "Back squat", prescription: "4 × 5 @ 225",
                  setsDone: 2, sets: 4, isCurrent: true),
        SVPlanRow(id: 2, name: "Romanian deadlift", prescription: "3 × 8 @ 185",
                  setsDone: 0, sets: 3),
        SVPlanRow(id: 3, name: "Leg press", prescription: "3 × 10 @ 270",
                  setsDone: 0, sets: 3),
        SVPlanRow(id: 4, name: "Walking lunge", prescription: "3 × 20 steps",
                  setsDone: 0, sets: 3),
    ]

    static let crewRungLine = "Today's rung: Back squat 4 × 5 @ 225 · week 3 of 8"

    // MARK: Warm-up (frame 122)

    static let soloRungLine = "Today's rung: Bench 4 × 5 @ 225"

    // MARK: Rounds (frames 123-124)

    /// 128 falling to 96 across the 1:42 of rest — the recovery as a shape
    /// rather than as two numbers with an arrow between them. Ten samples,
    /// one every ten seconds or so; pinned, not sampled from anything.
    static let restCurve = [128, 125, 121, 116, 111, 107, 103, 100, 98, 96]

    static let coachThreadTitle = "This session's Coach thread"
    static let coachThreadDetail = "3 messages · shared by the crew"
    static let coachThreadNote = "Unlocked for the whole crew because Mo is Pro."

    /// Spotter mode: the crew's live readings while they lift. Neutral ink,
    /// zone as a word — the owner's ruling.
    static let spotterHeartRates: [(name: String, bpm: Int, isLifting: Bool)] = [
        ("Dana Kord", 158, true),
        ("Lee Vance", 121, false),
        ("Sam Obi", 143, false),
        ("Mo Adeyemi", 132, false),
    ]

    // MARK: The swap card (frame 125)

    static let swapNowDetail = "4 × 5 @ 225 · what the crew is on now"
    static let swapProposedDetail = "4 × 5 @ 205 · Dana's proposal"

    // MARK: The pump card's caption (frame 119, no new id)

    static let pumpPhotoCaption = "Tap for the full workout"
}

// MARK: - The page

/// The v2 page: the same header and the same foot as `SVScreen`, with the
/// body in a `ScrollView` and the foot PINNED.
///
/// Why the change: the owner's second pass asks these screens to carry more
/// — the whole plan, the crew's buy-in, a Coach entry, a graph — and a fixed
/// page that overflows CLIPS its foot, which would hide the primary the frame
/// exists to show. A pinned foot over a scrolling body is also what the
/// shipped session screens do. When the content fits, this renders exactly as
/// `SVScreen` does: content at the top, foot at the bottom, nothing moved.
struct SVScrollScreen<Content: View, Foot: View>: View {
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

// MARK: - The plan, in full

/// The whole session as rows, with the columns ALIGNED: the prescription
/// column has one right edge, the progress column one width, the swap
/// control one position. A plan whose numbers do not line up cannot be
/// scanned, and scanning it is the only reason to show all four rows.
struct SVPlanListCard: View {
    @Environment(\.gsTheme) private var theme

    let kicker: String
    let rungLine: String
    let rows: [SVPlanRow]
    /// The leader can swap any row before Start (spec §3.1's plan card owns
    /// the swap control). Flat furniture on a raised card, never accent.
    var showsSwap: Bool = false
    /// Mid-session: how far into each exercise the crew is.
    var showsProgress: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GSSectionHeader(kicker)
            Text(rungLine)
                .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            GSDivider()
            ForEach(rows) { row in
                planRow(row)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private func planRow(_ row: SVPlanRow) -> some View {
        HStack(spacing: 8) {
            // A fixed 4 pt gutter so the current row's mark cannot shift the
            // names out of their column.
            RoundedRectangle(cornerRadius: 2)
                .fill(row.isCurrent && showsProgress ? theme.text : Color.clear)
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

            if showsProgress {
                Text("\(row.setsDone)/\(row.sets)")
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(row.isCurrent ? theme.text : theme.neutral500)
                    .frame(width: 32, alignment: .trailing)
            }

            if showsSwap { swapChip }
        }
        // A FIXED row height, so four rows make four straight edges whether
        // or not a row carries a chip or a progress count.
        .frame(height: 28)
    }

    private var swapChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
            Text("Swap")
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
        }
        .foregroundStyle(theme.neutral700)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.neutral300)
        .clipShape(Capsule())
        .fixedSize()
    }
}

// MARK: - Coach, as an entry row

/// Coach's door: one strip, one tap, a seeded thread (rule 7). The same
/// object serves the lobby ("Talk to Coach — this session's focus, form
/// questions, demo videos") and the round screens ("This session's Coach
/// thread · 3 messages"), because two doors to one room is two rooms.
///
/// Not accent. The screen's accent is its primary act, and Coach is reachable
/// in one tap from everywhere — an entry that shouts on every screen it
/// appears on stops being a door and becomes a banner.
struct SVCoachEntryRow: View {
    @Environment(\.gsTheme) private var theme

    let title: String
    let detail: String
    /// The line that says why this is available at all — the crew's Coach
    /// thread is Pro, and the fixture says whose.
    var note: String? = nil

    var body: some View {
        Button(action: {}) {
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
            .svStrip()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Readouts

/// The recovery as a CURVE. Round 1 printed `128 → 96`, which says where the
/// heart started and stopped and nothing about whether it is still falling —
/// which is the whole question a lifter asks at 1:42 of rest.
///
/// NEUTRAL INK, no zone tint: the owner's ruling for this pass. The shape
/// carries the meaning and the two labels carry the numbers.
struct SVHRRestGraph: View {
    @Environment(\.gsTheme) private var theme

    let samples: [Int]
    let duration: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GSSectionHeader("RECOVERY")
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(samples.first ?? 0)")
                    .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral500)
                    .fixedSize()
                curve
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(samples.last ?? 0)")
                        .font(GSFont.bold(17, relativeTo: .headline))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                    Text("BPM")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.5)
                        .foregroundStyle(theme.neutral500)
                }
                .fixedSize()
            }
            .frame(height: 40)
            Text("over \(duration) of rest")
                .font(GSFont.body(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
    }

    /// `topLeading` so an offset of (0, 0) puts a child's top-left corner in
    /// the corner — which makes the endpoint dot's placement arithmetic the
    /// same arithmetic the path uses, minus half the dot.
    private var curve: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                path(width: w, height: h)
                    .stroke(theme.neutral700,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(theme.text)
                    .frame(width: 6, height: 6)
                    .offset(x: w - 3,
                            y: point(index: samples.count - 1, height: h) - 3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// y measured from the TOP, so the highest reading sits highest.
    private func point(index: Int, height: CGFloat) -> CGFloat {
        guard let lo = samples.min(), let hi = samples.max(), hi > lo,
              samples.indices.contains(index) else { return height }
        let share = CGFloat(samples[index] - lo) / CGFloat(hi - lo)
        return height - (height * share)
    }

    private func path(width: CGFloat, height: CGFloat) -> Path {
        Path { p in
            guard samples.count > 1 else { return }
            let step = width / CGFloat(samples.count - 1)
            for index in samples.indices {
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

/// One lifter's live heart rate: name, number, zone as a WORD. Neutral ink
/// throughout (the owner's ruling), fixed column widths so four of these
/// stack into three straight edges.
struct SVLiveHRRow: View {
    @Environment(\.gsTheme) private var theme

    let name: String
    let bpm: Int
    /// The one who is lifting right now. Marked by WEIGHT, not by colour —
    /// no readout in this round spends accent.
    var isLifting: Bool = false
    /// THE OWNER'S REVERSAL (third pass): heart-rate zone colours stay, as an
    /// explicit exception to the colour rules. `true` tints the NUMBER with
    /// `SVZoneColor.of(bpm)` — the same mapping, the same tokens and the same
    /// values `together-clock` (v1) paints its bars and its `GSHeartRatePill`s
    /// with, so two frames cannot disagree about what 158 looks like. `BPM`
    /// stays `neutral500` and the zone word stays `neutral700`, which is
    /// exactly how the pill treats its own caption. Defaulted false, so
    /// `round-spotter-v2` is untouched.
    var zoneTinted: Bool = false

    private var numberInk: Color {
        zoneTinted ? SVZoneColor.of(bpm) : theme.text
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(isLifting ? "\(name) · lifting" : name)
                .font(isLifting ? GSFont.bold(12.5, relativeTo: .caption)
                                : GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(isLifting ? theme.text : theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text("\(bpm)")
                .font(GSFont.bold(15, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(numberInk)
                .frame(width: 34, alignment: .trailing)
            Text("BPM")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
                .frame(width: 26, alignment: .leading)
            Text(SVZoneWord.of(bpm))
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(theme.neutral700)
                .frame(width: 22, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

#endif
